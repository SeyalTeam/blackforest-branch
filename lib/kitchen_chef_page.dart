import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';

class KitchenChefPage extends StatefulWidget {
  final String? kitchenId;
  final String? kitchenName;
  final bool showNamesOnly;

  const KitchenChefPage({
    super.key,
    this.kitchenId,
    this.kitchenName,
    this.showNamesOnly = false,
  });

  @override
  State<KitchenChefPage> createState() => _KitchenChefPageState();
}

class _KitchenChefPageState extends State<KitchenChefPage> {
  List<dynamic> _chefs = [];
  List<dynamic> _kitchens = [];
  List<dynamic> _chefEmployees = [];
  bool _isLoading = true;
  bool _isCreatingChef = false;
  String _errorMessage = '';
  String? _branchId;
  String? _branchName;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  String _extractId(dynamic obj) {
    if (obj == null) return '';
    if (obj is String) return obj;
    if (obj is Map) {
      final nestedValue = obj['value'];
      if (nestedValue is Map) {
        return (nestedValue['id'] ??
                nestedValue['_id'] ??
                nestedValue[r'$oid'] ??
                '')
            .toString();
      }
      return (obj['id'] ?? obj['_id'] ?? obj[r'$oid'] ?? obj['value'] ?? '')
          .toString();
    }
    return '';
  }

  String _extractName(dynamic obj) {
    if (obj == null) return 'Unknown';
    if (obj is String) return obj;
    if (obj is Map) {
      final nestedValue = obj['value'];
      if (nestedValue is Map) {
        return (nestedValue['name'] ??
                nestedValue['title'] ??
                nestedValue['label'] ??
                nestedValue['email'] ??
                'Unknown')
            .toString();
      }
      return (obj['name'] ??
              obj['title'] ??
              obj['label'] ??
              obj['email'] ??
              'Unknown')
          .toString();
    }
    return 'Unknown';
  }

  List<dynamic> _decodeDocs(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map && decoded['docs'] is List) {
      return List<dynamic>.from(decoded['docs'] as List);
    }
    if (decoded is List) {
      return List<dynamic>.from(decoded);
    }
    return [];
  }

  String _extractErrorMessage(String responseBody, int statusCode) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty) {
          final first = errors.first;
          if (first is Map && first['message'] != null) {
            return first['message'].toString();
          }
        }
        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }
      }
    } catch (_) {}
    return 'Request failed ($statusCode)';
  }

  bool _isChefEmployee(dynamic employee) {
    if (employee is! Map) return false;

    final team = employee['team'];
    if (team == null) return false;

    if (team is String) {
      return team.toLowerCase().trim() == 'chef';
    }

    if (team is Map) {
      return _extractName(team).toLowerCase().trim() == 'chef';
    }

    if (team is List) {
      for (final item in team) {
        if (item is String && item.toLowerCase().trim() == 'chef') {
          return true;
        }
        if (item is Map && _extractName(item).toLowerCase().trim() == 'chef') {
          return true;
        }
      }
    }

    return false;
  }

  bool _containsBranchReference(dynamic value, String branchId) {
    if (branchId.isEmpty || value == null) return false;

    if (value is String) {
      return value == branchId;
    }

    if (value is Map) {
      final id = _extractId(value);
      if (id == branchId) return true;

      if (_containsBranchReference(value['value'], branchId)) return true;
      if (_containsBranchReference(value['branch'], branchId)) return true;
      if (_containsBranchReference(value['branches'], branchId)) return true;
      return false;
    }

    if (value is List) {
      for (final item in value) {
        if (_containsBranchReference(item, branchId)) return true;
      }
    }

    return false;
  }

  bool _chefBelongsToBranch(dynamic chef, String branchId) {
    if (chef is! Map || branchId.isEmpty) return false;

    if (_containsBranchReference(chef['branch'], branchId)) return true;
    if (_containsBranchReference(chef['kitchenBranches'], branchId)) {
      return true;
    }
    if (_containsBranchReference(chef['kitchen'], branchId)) return true;

    return false;
  }

  dynamic _findKitchenById(String kitchenId) {
    for (final kitchen in _kitchens) {
      if (_extractId(kitchen) == kitchenId) return kitchen;
    }
    return null;
  }

  List<dynamic> _categoriesForKitchenIds(List<String> kitchenIds) {
    final categories = <dynamic>[];
    final seenIds = <String>{};

    for (final kitchenId in kitchenIds) {
      final kitchenDoc = _findKitchenById(kitchenId);
      if (kitchenDoc is Map && kitchenDoc['categories'] is List) {
        final kitchenCategories = kitchenDoc['categories'] as List;
        for (final category in kitchenCategories) {
          final categoryId = _extractId(category);
          if (categoryId.isEmpty || seenIds.contains(categoryId)) continue;
          seenIds.add(categoryId);
          categories.add(category);
        }
      }
    }

    return categories;
  }

  Future<List<dynamic>> _fetchChefEmployees(
    String token,
    String? branchId,
  ) async {
    final branchFilter = (branchId != null && branchId.isNotEmpty)
        ? '&where[branch][equals]=$branchId'
        : '';

    final attempts = [
      '${ApiConfig.baseUrl}/employees?depth=1&limit=300&where[team][equals]=chef$branchFilter',
      '${ApiConfig.baseUrl}/employees?depth=1&limit=300&where[team][equals]=chef',
      '${ApiConfig.baseUrl}/employees?depth=1&limit=300',
    ];

    for (int i = 0; i < attempts.length; i++) {
      final res = await http.get(
        Uri.parse(attempts[i]),
        headers: ApiConfig.getHeaders(token),
      );

      if (res.statusCode != 200) continue;

      final docs = _decodeDocs(res.body);

      if (i == attempts.length - 1) {
        return docs.where(_isChefEmployee).toList();
      }

      return docs.where(_isChefEmployee).toList();
    }

    return [];
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null || token.isEmpty) {
        setState(() {
          _errorMessage = 'No token found. Please login.';
          _isLoading = false;
        });
        return;
      }

      _branchName = prefs.getString('branchName');

      final userRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/users/me?depth=2'),
        headers: ApiConfig.getHeaders(token),
      );

      if (userRes.statusCode != 200) {
        throw Exception('Failed to get user data');
      }

      final userData = jsonDecode(userRes.body);
      final userDoc = userData['user'] ?? userData;

      final branchId = _extractId(userDoc['branch']);
      final branchNameFromUser = _extractName(userDoc['branch']);

      final normalizedBranchId = branchId.isNotEmpty ? branchId : null;
      if (branchNameFromUser != 'Unknown' && branchNameFromUser.isNotEmpty) {
        _branchName = branchNameFromUser;
      }

      final branchFilterChef =
          (normalizedBranchId != null && normalizedBranchId.isNotEmpty)
          ? '&where[branch][equals]=$normalizedBranchId'
          : '';

      final fallbackBranchFilterChefEquals =
          (normalizedBranchId != null && normalizedBranchId.isNotEmpty)
          ? '&where[kitchenBranches][equals]=$normalizedBranchId'
          : '';

      final fallbackBranchFilterChefIn =
          (normalizedBranchId != null && normalizedBranchId.isNotEmpty)
          ? '&where[kitchenBranches][in][0]=$normalizedBranchId'
          : '';

      final kitchenFilterChef =
          (widget.kitchenId != null && widget.kitchenId!.isNotEmpty)
          ? '&where[kitchen][equals]=${widget.kitchenId}'
          : '';

      final branchFilterKitchen =
          (normalizedBranchId != null && normalizedBranchId.isNotEmpty)
          ? '&where[branches][in][0]=$normalizedBranchId'
          : '';

      final kitchensRes = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/kitchens?depth=1&limit=200$branchFilterKitchen',
        ),
        headers: ApiConfig.getHeaders(token),
      );

      if (kitchensRes.statusCode != 200) {
        throw Exception('Failed to fetch kitchens');
      }

      final kitchens = _decodeDocs(kitchensRes.body);
      List<dynamic> chefEmployees = [];
      if (!widget.showNamesOnly) {
        chefEmployees = await _fetchChefEmployees(token, normalizedBranchId);
      }

      List<dynamic> chefs = [];
      List<dynamic> firstSuccessfulDocs = [];
      final chefQueries = [
        '${ApiConfig.baseUrl}/users?where[role][equals]=chef$branchFilterChef$kitchenFilterChef&depth=1&limit=200',
        '${ApiConfig.baseUrl}/users?where[role][equals]=chef$fallbackBranchFilterChefEquals$kitchenFilterChef&depth=1&limit=200',
        '${ApiConfig.baseUrl}/users?where[role][equals]=chef$fallbackBranchFilterChefIn$kitchenFilterChef&depth=1&limit=200',
        '${ApiConfig.baseUrl}/users?where[role][equals]=chef$kitchenFilterChef&depth=1&limit=200',
      ];

      for (final query in chefQueries) {
        final chefsRes = await http.get(
          Uri.parse(query),
          headers: ApiConfig.getHeaders(token),
        );
        if (chefsRes.statusCode == 200) {
          final docs = _decodeDocs(chefsRes.body);
          if (firstSuccessfulDocs.isEmpty) {
            firstSuccessfulDocs = docs;
          }
          if (docs.isNotEmpty) {
            chefs = docs;
            break;
          }
        }
      }

      if (chefs.isEmpty && firstSuccessfulDocs.isNotEmpty) {
        chefs = firstSuccessfulDocs;
      }

      if (normalizedBranchId != null &&
          normalizedBranchId.isNotEmpty &&
          chefs.isNotEmpty) {
        final branchFilteredChefs = chefs
            .where((chef) => _chefBelongsToBranch(chef, normalizedBranchId))
            .toList();
        if (branchFilteredChefs.isNotEmpty) {
          chefs = branchFilteredChefs;
        }
      }

      setState(() {
        _branchId = normalizedBranchId;
        _chefs = chefs;
        _kitchens = kitchens;
        _chefEmployees = chefEmployees;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveChefAssignments(
    String chefId,
    List<String> kitchenIds,
    List<String> categoryIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Find other chefs to update first (removing swapped categories)
      final otherChefsToUpdate = <String, Map<String, dynamic>>{};
      final otherChefsNames = <String, String>{};
      for (final otherChef in _chefs) {
        final otherChefId = _extractId(otherChef);
        if (otherChefId != chefId && otherChefId.isNotEmpty) {
          if (otherChef is Map && otherChef['categories'] is List) {
            final otherChefCategories = otherChef['categories'] as List;
            final updatedCategoryIds = <String>[];
            bool modified = false;

            for (final cat in otherChefCategories) {
              final catId = _extractId(cat);
              if (catId.isNotEmpty) {
                if (categoryIds.contains(catId)) {
                  modified = true;
                } else {
                  updatedCategoryIds.add(catId);
                }
              }
            }

            if (modified) {
              final otherKitchenIds = <String>[];
              if (otherChef['kitchen'] is List) {
                for (final k in otherChef['kitchen'] as List) {
                  final kId = _extractId(k);
                  if (kId.isNotEmpty) otherKitchenIds.add(kId);
                }
              }
              otherChefsToUpdate[otherChefId] = {
                'kitchen': otherKitchenIds,
                'categories': updatedCategoryIds,
              };
              otherChefsNames[otherChefId] = _extractName(otherChef);
            }
          }
        }
      }

      // Perform updates for other chefs first
      for (final entry in otherChefsToUpdate.entries) {
        final otherChefId = entry.key;
        final payload = entry.value;
        final nameOfOtherChef = otherChefsNames[otherChefId] ?? 'other chef';

        final otherRes = await http.patch(
          Uri.parse('${ApiConfig.baseUrl}/users/$otherChefId'),
          headers: ApiConfig.getHeaders(token),
          body: jsonEncode(payload),
        );

        if (otherRes.statusCode != 200) {
          throw Exception(
            'Failed to update assignments for $nameOfOtherChef: '
            '${_extractErrorMessage(otherRes.body, otherRes.statusCode)}',
          );
        }
      }

      final body = {'kitchen': kitchenIds, 'categories': categoryIds};

      final res = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/users/$chefId'),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode(body),
      );

      if (mounted) {
        Navigator.pop(context);
      }

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Chef assignments updated successfully'),
            ),
          );
        }
        _fetchData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_extractErrorMessage(res.body, res.statusCode)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _createChefUser({
    required String name,
    required String email,
    required String password,
    required List<String> kitchenIds,
    required List<String> categoryIds,
    required String employeeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) return;

    if (_branchId == null || _branchId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to detect branch for chef creation.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isCreatingChef = true;
    });

    try {
      final payload = {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'role': 'chef',
        'branch': _branchId,
        'kitchen': kitchenIds,
        'categories': categoryIds,
        'employee': employeeId,
      };

      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/users'),
        headers: ApiConfig.getHeaders(token),
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chef user created successfully.')),
          );
        }
        await _fetchData();
        return;
      }

      var message = _extractErrorMessage(res.body, res.statusCode);
      final lower = message.toLowerCase();
      final isChefFieldIssue =
          lower.contains('branch') ||
          lower.contains('kitchen') ||
          lower.contains('categor') ||
          lower.contains('field');

      if (isChefFieldIssue) {
        message =
            '$message. Backend Users update for chef branch/kitchen/categories may still be pending.';
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating chef user: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingChef = false;
        });
      }
    }
  }

  Future<void> _showCreateChefDialog() async {
    if (_branchId == null || _branchId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login as a branch user to create chefs.'),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    final selectedKitchenIds = <String>[];
    if (widget.kitchenId != null && widget.kitchenId!.isNotEmpty) {
      selectedKitchenIds.add(widget.kitchenId!);
    }
    final selectedCategoryIds = <String>[];
    String? selectedEmployeeId;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final availableCategories = _categoriesForKitchenIds(
              selectedKitchenIds,
            );
            final availableCategoryIds = availableCategories
                .map((c) => _extractId(c))
                .where((id) => id.isNotEmpty)
                .toSet();
            selectedCategoryIds.removeWhere(
              (id) => !availableCategoryIds.contains(id),
            );

            final employeeItems = _chefEmployees
                .where((e) => _extractId(e).isNotEmpty)
                .toList();

            if (selectedEmployeeId != null &&
                employeeItems
                    .where((e) => _extractId(e) == selectedEmployeeId)
                    .isEmpty) {
              selectedEmployeeId = null;
            }

            return AlertDialog(
              title: const Text('Create Chef User'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Name is required';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return 'Email is required';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.isEmpty) return 'Password is required';
                            if (password.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        const Text('Role: chef'),
                        const SizedBox(height: 4),
                        Text(
                          'Branch: ${_branchName ?? _branchId}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Kitchen',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (_kitchens.isEmpty)
                          const Text(
                            'No kitchens available for this branch.',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _kitchens.map((kitchen) {
                              final kitchenId = _extractId(kitchen);
                              final isSelected = selectedKitchenIds.contains(
                                kitchenId,
                              );
                              return FilterChip(
                                label: Text(_extractName(kitchen)),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedKitchenIds.add(kitchenId);
                                    } else {
                                      selectedKitchenIds.remove(kitchenId);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          'Categories',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (availableCategories.isEmpty)
                          const Text(
                            'Select at least one kitchen to view categories.',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availableCategories.map((category) {
                              final categoryId = _extractId(category);
                              final isSelected = selectedCategoryIds.contains(
                                categoryId,
                              );
                              return FilterChip(
                                label: Text(_extractName(category)),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedCategoryIds.add(categoryId);
                                    } else {
                                      selectedCategoryIds.remove(categoryId);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedEmployeeId,
                          decoration: const InputDecoration(
                            labelText: 'Employee (team = chef)',
                          ),
                          items: employeeItems
                              .map(
                                (employee) => DropdownMenuItem<String>(
                                  value: _extractId(employee),
                                  child: Text(_extractName(employee)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedEmployeeId = value;
                            });
                          },
                        ),
                        if (employeeItems.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'No chef-team employees found.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isCreatingChef
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          if (selectedKitchenIds.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select at least one kitchen.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (selectedCategoryIds.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select at least one category.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (selectedEmployeeId == null ||
                              selectedEmployeeId!.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please select a chef employee.'),
                              ),
                            );
                            return;
                          }

                          Navigator.pop(dialogContext);

                          await _createChefUser(
                            name: nameController.text,
                            email: emailController.text,
                            password: passwordController.text,
                            kitchenIds: selectedKitchenIds,
                            categoryIds: selectedCategoryIds,
                            employeeId: selectedEmployeeId!,
                          );
                        },
                  child: _isCreatingChef
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Chef'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
  }

  void _showAssignDialog(dynamic chef) {
    final chefId = _extractId(chef);
    final selectedKitchenIds = <String>[];
    final selectedCategoryIds = <String>[];

    if (chef['kitchen'] is List) {
      final kitchens = chef['kitchen'] as List;
      for (final kitchen in kitchens) {
        final id = _extractId(kitchen);
        if (id.isNotEmpty) selectedKitchenIds.add(id);
      }
    }

    if (chef['categories'] is List) {
      final categories = chef['categories'] as List;
      for (final category in categories) {
        final id = _extractId(category);
        if (id.isNotEmpty) selectedCategoryIds.add(id);
      }
    }

    // Build a map of categoryId -> assigned chef's name
    final categoryToChefMap = <String, String>{};
    for (final otherChef in _chefs) {
      final otherChefId = _extractId(otherChef);
      if (otherChefId != chefId) {
        final otherChefName = _extractName(otherChef);
        if (otherChef is Map && otherChef['categories'] is List) {
          for (final category in otherChef['categories'] as List) {
            final catId = _extractId(category);
            if (catId.isNotEmpty) {
              categoryToChefMap[catId] = otherChefName;
            }
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allAvailableCategories = _categoriesForKitchenIds(
              selectedKitchenIds,
            );

            // Map all categories, appending currently assigned chef's name if applicable
            final availableCategories = allAvailableCategories.map((c) {
              if (c is Map) {
                final catId = _extractId(c);
                final assignedChefName = categoryToChefMap[catId];
                if (assignedChefName != null && assignedChefName.isNotEmpty) {
                  final cloned = Map<String, dynamic>.from(c);
                  final originalName = _extractName(c);
                  cloned['name'] = '$originalName ($assignedChefName)';
                  return cloned;
                }
              }
              return c;
            }).toList();

            final availableCategoryIds = availableCategories
                .map((c) => _extractId(c))
                .where((id) => id.isNotEmpty)
                .toSet();

            selectedCategoryIds.removeWhere(
              (id) => !availableCategoryIds.contains(id),
            );

            final kitchenSelectionText = _selectionSummary(
              selectedKitchenIds,
              _kitchens,
              placeholder: 'Select kitchen',
            );
            final categorySelectionText = _selectionSummary(
              selectedCategoryIds,
              availableCategories,
              placeholder: 'Select category',
            );

            return AlertDialog(
              title: Text('Assign Kitchen & Category: ${_extractName(chef)}'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _kitchens.isEmpty
                            ? null
                            : () async {
                                final selected = await _showMultiSelectPicker(
                                  context: dialogContext,
                                  title: 'Select Kitchens',
                                  options: _kitchens,
                                  initiallySelectedIds: selectedKitchenIds,
                                  emptyMessage: 'No kitchens available.',
                                );
                                if (selected == null) return;
                                setDialogState(() {
                                  selectedKitchenIds
                                    ..clear()
                                    ..addAll(selected);
                                });
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Kitchen (multi-select)',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          child: Text(kitchenSelectionText),
                        ),
                      ),
                      if (_kitchens.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'No kitchens available.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: availableCategories.isEmpty
                            ? null
                            : () async {
                                final selected = await _showMultiSelectPicker(
                                  context: dialogContext,
                                  title: 'Select Categories',
                                  options: availableCategories,
                                  initiallySelectedIds: selectedCategoryIds,
                                  emptyMessage:
                                      'Select kitchen first to load categories.',
                                );
                                if (selected == null) return;
                                setDialogState(() {
                                  selectedCategoryIds
                                    ..clear()
                                    ..addAll(selected);
                                });
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Category (multi-select)',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          child: Text(categorySelectionText),
                        ),
                      ),
                      if (availableCategories.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Select a kitchen first to view categories.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _saveChefAssignments(
                      chefId,
                      selectedKitchenIds,
                      selectedCategoryIds,
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildChefCard(dynamic chef) {
    final name = _extractName(chef);
    final employeeName = chef is Map && chef['employee'] != null
        ? _extractName(chef['employee'])
        : null;

    final kitchenNames = <String>[];
    if (chef is Map && chef['kitchen'] is List) {
      final kitchens = chef['kitchen'] as List;
      for (final kitchen in kitchens) {
        kitchenNames.add(_extractName(kitchen));
      }
    }

    final categoryNames = <String>[];
    if (chef is Map && chef['categories'] is List) {
      final categories = chef['categories'] as List;
      for (final category in categories) {
        categoryNames.add(_extractName(category));
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAssignDialog(chef),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: const Icon(Icons.person, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit, color: Colors.grey, size: 20),
                ],
              ),
              if (employeeName != null && employeeName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Employee: $employeeName',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
              const SizedBox(height: 16),
              if (kitchenNames.isNotEmpty) ...[
                const Text(
                  'Kitchens:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kitchenNames
                      .map(
                        (kitchenName) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            border: Border.all(color: Colors.orange.shade200),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            kitchenName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              if (categoryNames.isNotEmpty) ...[
                const Text(
                  'Categories:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: categoryNames
                      .map(
                        (categoryName) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green.shade200),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            categoryName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (kitchenNames.isEmpty && categoryNames.isEmpty)
                const Text(
                  'No kitchens or categories assigned',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChefNameTile(dynamic chef) {
    final name = _extractName(chef);

    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(name),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () => _showAssignDialog(chef),
    );
  }

  String _selectionSummary(
    List<String> selectedIds,
    List<dynamic> options, {
    required String placeholder,
  }) {
    if (selectedIds.isEmpty) return placeholder;

    final names = <String>[];
    for (final selectedId in selectedIds) {
      for (final option in options) {
        if (_extractId(option) == selectedId) {
          names.add(_extractName(option));
          break;
        }
      }
    }

    if (names.isEmpty) return placeholder;
    return names.join(', ');
  }

  Future<List<String>?> _showMultiSelectPicker({
    required BuildContext context,
    required String title,
    required List<dynamic> options,
    required List<String> initiallySelectedIds,
    required String emptyMessage,
  }) async {
    final selectedIds = <String>{...initiallySelectedIds};

    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: options.isEmpty
                          ? Center(
                              child: Text(
                                emptyMessage,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options[index];
                                final id = _extractId(option);
                                final label = _extractName(option);
                                final isChecked = selectedIds.contains(id);

                                return CheckboxListTile(
                                  value: isChecked,
                                  title: Text(label),
                                  onChanged: (checked) {
                                    setSheetState(() {
                                      if ((checked ?? false) && id.isNotEmpty) {
                                        selectedIds.add(id);
                                      } else {
                                        selectedIds.remove(id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                selectedIds.toList(),
                              ),
                              child: const Text('Done'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.showNamesOnly
        ? 'Chef Names'
        : (widget.kitchenName != null
              ? 'Chefs - ${widget.kitchenName}'
              : 'Kitchen & Chef Assignment');

    return CommonScaffold(
      title: title,
      pageType: PageType.home,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : widget.showNamesOnly
          ? (_chefs.isEmpty
                ? const Center(child: Text('No chefs found for this branch.'))
                : RefreshIndicator(
                    onRefresh: _fetchData,
                    child: ListView.builder(
                      itemCount: _chefs.length,
                      itemBuilder: (context, index) {
                        return _buildChefNameTile(_chefs[index]);
                      },
                    ),
                  ))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _branchName != null && _branchName!.isNotEmpty
                              ? 'Branch: $_branchName'
                              : (_branchId != null
                                    ? 'Branch ID: $_branchId'
                                    : 'Branch not detected'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isCreatingChef
                            ? null
                            : _showCreateChefDialog,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Add Chef'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _chefs.isEmpty
                      ? const Center(
                          child: Text('No chefs found for this branch.'),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchData,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 12),
                            itemCount: _chefs.length,
                            itemBuilder: (context, index) {
                              return _buildChefCard(_chefs[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
