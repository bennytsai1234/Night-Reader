import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'source_manager_provider.dart';
import 'package:night_reader/core/models/book_source.dart';

class ExploreSourcesPage extends StatefulWidget {
  const ExploreSourcesPage({super.key});

  @override
  State<ExploreSourcesPage> createState() => _ExploreSourcesPageState();
}

class _ExploreSourcesPageState extends State<ExploreSourcesPage> {
  static const _prefsKey = 'source_library_repos';
  static const _defaultRepos = [
    {
      'name': 'Legado 官方書源庫 (Yuedu)',
      'url':
          'https://raw.githubusercontent.com/gedoor/legado/master/app/src/main/assets/default_book_sources.json',
    },
    {
      'name': '開源書源分享庫 1',
      'url':
          'https://raw.githubusercontent.com/yuedu-source/yuedu-source/main/source.json',
    },
  ];

  List<Map<String, String>> _repositories = [];
  bool _isLoading = false;
  List<BookSource> _fetchedSources = [];
  Set<int> _selectedIndices = {};
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  Future<void> _loadRepos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as List;
      setState(() {
        _repositories =
            decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      });
    } else {
      setState(() {
        _repositories =
            _defaultRepos.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  Future<void> _saveRepos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_repositories));
  }

  void _showAddRepoDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('新增書源庫'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名稱',
                    hintText: '我的書源庫',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://...',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  if (name.isNotEmpty && url.isNotEmpty) {
                    setState(() {
                      _repositories.add({'name': name, 'url': url});
                    });
                    _saveRepos();
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('新增'),
              ),
            ],
          ),
    );
  }

  void _deleteRepo(int index) {
    setState(() {
      _repositories.removeAt(index);
    });
    _saveRepos();
  }

  Future<void> _fetchSources(String url) async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
      _fetchedSources = [];
      _selectedIndices = {};
    });

    try {
      final response = await Dio().get(url);
      if (response.data != null) {
        dynamic decoded;
        if (response.data is String) {
          decoded = jsonDecode(response.data);
        } else {
          decoded = response.data;
        }

        var sources = <BookSource>[];
        if (decoded is List) {
          sources =
              decoded
                  .map((e) => BookSource.fromJson(e as Map<String, dynamic>))
                  .toList();
        } else if (decoded is Map) {
          sources = [BookSource.fromJson(decoded as Map<String, dynamic>)];
        }

        setState(() {
          _fetchedSources = sources;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = '獲取失敗: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _importSelected() async {
    if (_selectedIndices.isEmpty) return;

    final provider = context.read<SourceManagerProvider>();
    final toImport = _selectedIndices
        .map((i) => _fetchedSources[i])
        .map((source) {
          if (source.isNovelTextSource) return source;
          source.enabled = false;
          source.enabledExplore = false;
          source.addGroup(nonNovelSourceGroupTag);
          return source;
        })
        .toList(growable: false);
    final count = await provider.importSources(toImport);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('成功匯入 $count 個書源')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('網路書源庫'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增書源庫',
            onPressed: _showAddRepoDialog,
          ),
          if (_selectedIndices.isNotEmpty)
            TextButton(
              onPressed: _importSelected,
              child: Text(
                '匯入 (${_selectedIndices.length})',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _repositories.length,
              itemBuilder: (context, index) {
                final repo = _repositories[index];
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: GestureDetector(
                    onLongPress: () {
                      showDialog(
                        context: context,
                        builder:
                            (ctx) => AlertDialog(
                              title: const Text('刪除書源庫'),
                              content: Text('確定刪除「${repo['name']}」？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _deleteRepo(index);
                                  },
                                  child: Text(
                                    '刪除',
                                    style: TextStyle(
                                      color: Theme.of(ctx).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                      );
                    },
                    child: ActionChip(
                      label: Text(repo['name']!),
                      onPressed: () => _fetchSources(repo['url']!),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMsg.isNotEmpty
                    ? Center(
                      child: Text(
                        _errorMsg,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    )
                    : _fetchedSources.isEmpty
                    ? const Center(child: Text('請選擇上方書源庫以載入資料'))
                    : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              Text(
                                '共 ${_fetchedSources.length} 個書源',
                                style: AppTextStyles.labelSm.copyWith(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    if (_selectedIndices.length ==
                                        _fetchedSources.length) {
                                      _selectedIndices.clear();
                                    } else {
                                      _selectedIndices = Set.from(
                                        List.generate(
                                          _fetchedSources.length,
                                          (i) => i,
                                        ),
                                      );
                                    }
                                  });
                                },
                                child: Text(
                                  _selectedIndices.length ==
                                          _fetchedSources.length
                                      ? '取消全選'
                                      : '全選',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _fetchedSources.length,
                            itemBuilder: (context, index) {
                              final source = _fetchedSources[index];
                              final isSelected = _selectedIndices.contains(
                                index,
                              );
                              return ListTile(
                                leading: Checkbox(
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedIndices.add(index);
                                      } else {
                                        _selectedIndices.remove(index);
                                      }
                                    });
                                  },
                                ),
                                title: Text(source.bookSourceName),
                                subtitle: Text(
                                  source.bookSourceUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIndices.remove(index);
                                    } else {
                                      _selectedIndices.add(index);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}
