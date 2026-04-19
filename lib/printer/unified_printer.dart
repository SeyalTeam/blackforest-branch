import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PrintPurpose { billing, kot, generic }

class UnifiedPrinter {
  final NetworkPrinter? networkPrinter;
  final Generator generator;
  final bool isBluetooth;
  final List<int> _bytes = [];

  UnifiedPrinter._({
    this.networkPrinter,
    required this.generator,
    required this.isBluetooth,
  });

  static Future<UnifiedPrinter?> connect({
    required String? printerIp,
    required List<int> candidatePorts,
    required PaperSize paperSize,
    required CapabilityProfile profile,
    PrintPurpose purpose = PrintPurpose.generic,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final generator = Generator(paperSize, profile);

    final bluetoothEnabled = prefs.getBool('bluetooth_printing_enabled') ?? true;
    final bluetoothMac = (prefs.getString('bt_printer_mac') ?? '').trim();
    if (bluetoothEnabled && bluetoothMac.isNotEmpty) {
      try {
        var isConnected = await PrintBluetoothThermal.connectionStatus;
        if (!isConnected) {
          await PrintBluetoothThermal.disconnect;
          await Future.delayed(const Duration(milliseconds: 500));

          isConnected = await PrintBluetoothThermal.connect(
            macPrinterAddress: bluetoothMac,
          );

          if (!isConnected) {
            await Future.delayed(const Duration(seconds: 1));
            isConnected = await PrintBluetoothThermal.connect(
              macPrinterAddress: bluetoothMac,
            );
          }
        }

        if (isConnected) {
          final printer = UnifiedPrinter._(
            generator: generator,
            isBluetooth: true,
          );
          printer._bytes.addAll(generator.reset());
          return printer;
        }
      } catch (error) {
        debugPrint('Bluetooth printer connection failed: $error');
      }
    }

    final wifiEnabled = prefs.getBool('wifi_printing_enabled') ?? true;
    final ip = (printerIp ?? '').trim();
    
    bool canUseWifi = wifiEnabled && ip.isNotEmpty;
    if (canUseWifi) {
      if (purpose == PrintPurpose.billing) {
        canUseWifi = prefs.getBool('wifi_billing_enabled') ?? true;
      } else if (purpose == PrintPurpose.kot) {
        canUseWifi = prefs.getBool('wifi_kot_enabled') ?? true;
      }
    }

    if (!canUseWifi) {
      return null;
    }

    final networkPrinter = NetworkPrinter(paperSize, profile);
    for (final port in candidatePorts.toSet()) {
      try {
        final result = await networkPrinter
            .connect(ip, port: port)
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () => PosPrintResult.timeout,
            );

        if (result == PosPrintResult.success) {
          return UnifiedPrinter._(
            networkPrinter: networkPrinter,
            generator: generator,
            isBluetooth: false,
          );
        }
      } catch (error) {
        debugPrint('Network printer connection failed on $ip:$port: $error');
      }
    }

    return null;
  }

  void text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    if (isBluetooth) {
      _bytes.addAll(
        generator.text(
          text,
          styles: styles,
          linesAfter: linesAfter,
          containsChinese: containsChinese,
          maxCharsPerLine: maxCharsPerLine,
        ),
      );
      return;
    }

    networkPrinter?.text(
      text,
      styles: styles,
      linesAfter: linesAfter,
      containsChinese: containsChinese,
      maxCharsPerLine: maxCharsPerLine,
    );
  }

  void hr({String ch = '-', int linesAfter = 0}) {
    if (isBluetooth) {
      _bytes.addAll(generator.hr(ch: ch, linesAfter: linesAfter));
      return;
    }

    networkPrinter?.hr(ch: ch, linesAfter: linesAfter);
  }

  void row(List<PosColumn> cols) {
    if (isBluetooth) {
      _bytes.addAll(generator.row(cols));
      return;
    }

    networkPrinter?.row(cols);
  }

  void feed(int n) {
    if (isBluetooth) {
      _bytes.addAll(generator.feed(n));
      return;
    }

    networkPrinter?.feed(n);
  }

  void rawBytes(List<int> command) {
    if (isBluetooth) {
      _bytes.addAll(generator.rawBytes(command));
      return;
    }

    networkPrinter?.rawBytes(command);
  }

  void emptyLines(int n) {
    if (isBluetooth) {
      _bytes.addAll(generator.emptyLines(n));
      return;
    }

    networkPrinter?.emptyLines(n);
  }

  void smallRowGap({int dots = 8}) {
    final safeDots = dots.clamp(1, 255);
    rawBytes([27, 51, safeDots]);
    emptyLines(1);
    rawBytes([27, 50]);
  }

  void image(img.Image imgSrc, {PosAlign align = PosAlign.center}) {
    if (isBluetooth) {
      _bytes.addAll(generator.image(imgSrc, align: align));
      return;
    }

    networkPrinter?.image(imgSrc, align: align);
  }

  void textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    if (isBluetooth) {
      _bytes.addAll(
        generator.textEncoded(
          textBytes,
          styles: styles,
          linesAfter: linesAfter,
          maxCharsPerLine: maxCharsPerLine,
        ),
      );
      return;
    }

    networkPrinter?.textEncoded(
      textBytes,
      styles: styles,
      linesAfter: linesAfter,
      maxCharsPerLine: maxCharsPerLine,
    );
  }

  void qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.Size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    if (isBluetooth) {
      _bytes.addAll(generator.qrcode(text, align: align, size: size, cor: cor));
      return;
    }

    networkPrinter?.qrcode(text, align: align, size: size, cor: cor);
  }

  void cut({PosCutMode mode = PosCutMode.full}) {
    if (isBluetooth) {
      _bytes.addAll(generator.cut(mode: mode));
      return;
    }

    networkPrinter?.cut(mode: mode);
  }

  Future<void> disconnectAndPrint() async {
    if (isBluetooth) {
      if (_bytes.isNotEmpty) {
        await PrintBluetoothThermal.writeBytes(_bytes);
      }
      return;
    }

    networkPrinter?.disconnect();
  }
}
