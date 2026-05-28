import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';

class ReplaceRuleProvider extends ChangeNotifier {
  final ReplaceRuleDao _dao = getIt<ReplaceRuleDao>();
  List<ReplaceRule> _rules = [];
  String _selectedGroup = '全部';
  bool _isLoading = false;

  List<ReplaceRule> get rules {
    if (_selectedGroup == '全部') return _rules;
    return _rules
        .where((r) => r.group?.contains(_selectedGroup) ?? false)
        .toList();
  }

  List<String> get groups {
    final allGroups = <String>{'全部'};
    for (var rule in _rules) {
      if (rule.group != null && rule.group!.isNotEmpty) {
        allGroups.addAll(rule.group!.split(',').map((e) => e.trim()));
      }
    }
    return allGroups.toList()..sort();
  }

  String get selectedGroup => _selectedGroup;
  bool get isLoading => _isLoading;

  void selectGroup(String group) {
    _selectedGroup = group;
    notifyListeners();
  }

  ReplaceRuleProvider() {
    loadRules();
  }

  Future<void> loadRules() async {
    _isLoading = true;
    notifyListeners();
    _rules = await _dao.getAll();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addRule(ReplaceRule rule) async {
    await _dao.upsert(rule);
    await loadRules();
  }

  Future<void> updateRule(ReplaceRule rule) async {
    await _dao.upsert(rule);
    await loadRules();
  }

  Future<void> deleteRule(int id) async {
    await _dao.deleteById(id);
    await loadRules();
  }

  Future<void> toggleEnabled(ReplaceRule rule) async {
    final newState = !rule.isEnabled;
    await _dao.updateEnabled(rule.id, newState);
    rule.isEnabled = newState;
    notifyListeners();
  }

  Future<void> updateOrder(int id, int order) async {
    await _dao.updateOrder(id, order);
    // Don't reload all for every reorder if using ReorderableListView,
    // but here we just keep it simple.
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final rule = _rules.removeAt(oldIndex);
    _rules.insert(newIndex, rule);
    notifyListeners();

    // Update all orders in DB
    for (var i = 0; i < _rules.length; i++) {
      _rules[i].order = i;
      await _dao.updateOrder(_rules[i].id, i);
    }
  }

  // --- 導入導出擴展 ---
  Future<int> importFromText(String jsonStr) async {
    var count = 0;
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      for (var item in list) {
        if (item is Map<String, dynamic>) {
          final rule = ReplaceRule.fromJson(item);
          await _dao.upsert(rule);
          count++;
        }
      }
      if (count > 0) {
        await loadRules();
      }
    } catch (e) {
      AppLog.e('匯入規則失敗: $e', error: e);
    }
    return count;
  }

  Future<void> exportToClipboard() async {
    try {
      final list = _rules.map((e) => e.toJson()).toList();
      final jsonStr = jsonEncode(list);
      await Clipboard.setData(ClipboardData(text: jsonStr));
    } catch (e) {
      AppLog.e('導出規則失敗: $e', error: e);
    }
  }
}
