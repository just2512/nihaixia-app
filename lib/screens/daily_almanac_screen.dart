import 'package:flutter/material.dart';

import '../utils/fold_aware_routes.dart';
import '../widgets/state_view.dart';
import 'package:nihaisha_app/services/lunar_almanac_service.dart';
import '../widgets/almanac_cards.dart';
import '../data/saved_chart_repository.dart';
import 'festival_lookup_screen.dart';

/// 滑动手势方向（纯函数 [resolveSwipe] 的判定结果）。
enum SwipeDir { dayNext, dayPrev }

/// 纯函数：依据手势速度分量判定滑动方向，便于单测。
///
/// 规则：只认横向手势——左滑（dx<0）切前一天，右滑（dx>0）切后一天。
/// 以下情形返回 null（不触发切换）：
/// - 横向速度绝对值不超过 40px/s（抖动）；
/// - 纵向速度不小于横向（纵向手势留给内容滚动，不再用于切日）。
SwipeDir? resolveSwipe(double dx, double dy) {
  if (dx.abs() <= 40 || dx.abs() <= dy.abs()) return null;
  return dx < 0 ? SwipeDir.dayPrev : SwipeDir.dayNext;
}

/// 每日黄历（老黄历）页面。
///
/// 基于 sxwnl_spa_dart 的农历，叠加建除十二神、彭祖百忌、冲煞、宜忌，
/// 年柱月柱日柱取自紫微引擎同一套四柱口径（见 [AlmanacDay.ganzhiYear]）。
/// 结果属「民俗文化参考」，非行事指令。
///
/// 交互：左滑切前一天、右滑切后一天（仅认横向拖拽，[resolveSwipe] 判定），
/// 纵向手势完全归列表滚动长内容，互不干扰。
class DailyAlmanacScreen extends StatefulWidget {
  const DailyAlmanacScreen({super.key, this.returnResultOnComplete = false});

  final bool returnResultOnComplete;

  @override
  State<DailyAlmanacScreen> createState() => _DailyAlmanacScreenState();
}

class _DailyAlmanacScreenState extends State<DailyAlmanacScreen> {
  DateTime _date = DateTime.now();
  AlmanacDay? _almanac;
  bool _loading = true;
  String? _userZodiac; // 本命生肖（最近命盘推导；null=未设置→不显预警）

  @override
  void initState() {
    super.initState();
    _compute();
    _loadUserZodiac();
  }

  /// 由最近一条已存命盘推导本命生肖，供「今日相冲」个性化预警。
  /// 无命盘/解析失败则静默保持 null，不影响黄历展示。
  Future<void> _loadUserZodiac() async {
    try {
      final charts = await SavedChartRepository.getAll();
      if (charts.isEmpty) return;
      final dt = DateTime.parse(charts.first.solarIso);
      final z = getUserZodiacFromSolar(dt);
      if (mounted) setState(() => _userZodiac = z);
    } catch (_) {
      // 命盘库不可用或解析失败：保持 null，预警静默关闭。
    }
  }

  void _compute() {
    setState(() => _loading = true);
    // 用 microtask 让 loading 先渲染，再算（农历/干支为纯本地计算，极快）。
    Future.microtask(() {
      final a = getDailyAlmanac(_date);
      if (mounted) {
        setState(() {
          _almanac = a;
          _loading = false;
        });
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      anchorPoint: foldAwareRouteAnchorPoint(context),
      initialDate: _date,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null && picked != _date) {
      setState(() => _date = picked);
      _compute();
    }
  }

  /// 按滑动方向切换日期：左滑 = 前一天 / 右滑 = 后一天。
  /// Dart 的 DateTime 自动处理跨月跨年（如 3 月 1 日往前一天为 2 月最后一日）。
  void _applySwipe(SwipeDir dir) {
    final delta = dir == SwipeDir.dayNext ? 1 : -1;
    _date = DateTime(_date.year, _date.month, _date.day + delta);
    _compute();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日黄历'),
        actions: [
          if (widget.returnResultOnComplete && _almanac != null)
            IconButton(
              tooltip: '返回 AI 助手',
              icon: const Icon(Icons.reply),
              onPressed: _returnAssistantResult,
            ),
          IconButton(
            tooltip: '查农历节日 / 神诞',
            icon: const Icon(Icons.festival_outlined),
            onPressed: () => Navigator.push(
              context,
              FoldAwareMaterialPageRoute(sourceContext: context, builder: (_) => const FestivalLookupScreen()),
            ),
          ),
          IconButton(
            tooltip: '选择日期',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickDate,
          ),
        ],
      ),
      body: GestureDetector(
        // 只认横向拖拽（onHorizontalDragEnd）：纵向滚动完全归 ListView，
        // 对角快滑不再误触切日（P1 修复：原 onPanEnd 靠横纵分量比较，
        // 斜向滑动会意外切日）。
        onHorizontalDragEnd: (details) {
          final v = details.velocity.pixelsPerSecond;
          final dir = resolveSwipe(v.dx, v.dy);
          if (dir != null) _applySwipe(dir);
        },
        child: ListView(
          // 不禁用滚动：内容较长时可滚到底部完整查看。
          padding: const EdgeInsets.all(16),
          children: [
            const AlmanacSwipeHint(),
            const AlmanacDisclaimer(),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: StateView.loading(),
                ),
              )
            else if (_almanac != null)
              ..._buildContent(_almanac!),
          ],
        ),
      ),
    );
  }


  void _returnAssistantResult() {
    final a = _almanac;
    if (a == null) return;
    final summary = [
      '每日黄历（民俗文化参考）',
      '公历：${a.solar.year}-${a.solar.month}-${a.solar.day} ${a.weekdayName}',
      '农历：${a.lunarText}',
      '干支：${a.ganzhiYear}年 ${a.ganzhiMonth}月 ${a.ganzhiDay}日',
      '建除：${a.jianChu}；冲煞：${a.chong}，${a.sha}',
      '宜：${a.yi.join('、')}',
      '忌：${a.ji.join('、')}',
      '吉时：${a.jiShi.join('、')}',
      '方位：财神${a.caiShen}；喜神${a.xiShen}；福神${a.fuShen}',
      if (a.solarTerm != null) '节气：${a.solarTerm}',
      '说明：传统通胜民俗信息，不是事实预测或行为指令。',
    ].join('\\n');
    Navigator.pop(context, summary);
  }

  List<Widget> _buildContent(AlmanacDay a) {
    return [
      AlmanacDateHeader(almanac: a),
      const SizedBox(height: 12),
      AlmanacJianChuCard(almanac: a),
      const SizedBox(height: 12),
      AlmanacZodiacChongCard(almanac: a, userZodiac: _userZodiac),
      const SizedBox(height: 12),
      AlmanacPengZuCard(almanac: a),
      const SizedBox(height: 12),
      AlmanacYiJiPairCard(yi: a.yi, ji: a.ji),
      const SizedBox(height: 12),
      AlmanacTongShengCard(almanac: a),
      if (a.festivals.isNotEmpty) ...[
        const SizedBox(height: 12),
        AlmanacFestivalCard(festivals: a.festivals),
      ],
      if (a.deityFestivals.isNotEmpty) ...[
        const SizedBox(height: 12),
        AlmanacDeityFestivalCard(festivals: a.deityFestivals),
      ],
      if (a.chaoshanFestivals.isNotEmpty) ...[
        const SizedBox(height: 12),
        AlmanacChaoshanCard(festivals: a.chaoshanFestivals),
      ],
    ];
  }
}
