import 'package:flutter/material.dart';
import '../utils/fold_aware_routes.dart';
import '../data/formula_repository.dart';
import '../data/herb_repository.dart';
import '../data/settings_repository.dart';
import '../engine/diagnostic_rules.dart';
import '../models/formula.dart';
import '../models/herb.dart';
import '../widgets/keep_alive_tab.dart';
import '../widgets/adaptive_master_detail.dart';
import '../widgets/meridian_icons.dart';
import '../widgets/solar_term_card.dart';
import '../theme/app_colors.dart';
import 'acupuncture_screen.dart';
import 'formula_detail_screen.dart';
import 'herb_detail_screen.dart';
import 'meridian_detail_screen.dart';
import 'neijing_knowledge_screen.dart';
import 'search_tab.dart';
import 'shanghan_jingui_screen.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('中医知识'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '六经'),
            Tab(text: '方剂'),
            Tab(text: '本草'),
            Tab(text: '针灸'),
            Tab(text: '内经'),
            Tab(text: '伤寒金匮'),
            Tab(text: '搜索'),
          ],
        ),
      ),
      body: Column(
        children: [
          // 节气卡占一屏高度；设置里可关掉（issue #4 反馈占屏比大）
          ListenableBuilder(
            listenable: SettingsRepository.instance,
            builder: (context, _) => SettingsRepository.instance.hideSolarTermCard
                ? const SizedBox.shrink()
                : const SolarTermCard(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                KeepAliveTab(child: _MeridianTab()),
                KeepAliveTab(child: _FormulaTab()),
                KeepAliveTab(child: _HerbTab()),
                const KeepAliveTab(child: AcupunctureScreen()),
                const KeepAliveTab(child: NeijingKnowledgeScreen()),
                const KeepAliveTab(child: ShangHanJinguiScreen()),
                const KeepAliveTab(child: SearchTab()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MeridianTab extends StatelessWidget {
  static const _meridianOrder = ['太阳', '阳明', '少阳', '太阴', '少阴', '厥阴'];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _meridianOrder.length,
      itemBuilder: (context, index) {
        final name = _meridianOrder[index];
        final details = DiagnosticRules.meridianDetails[name];
        if (details == null) return const SizedBox.shrink();

        final color = context.colors.meridianColor(name);
        final healingTime = DiagnosticRules.meridianHealingTime[name] ?? '';
        final formulas = details['formulas'] as List<String>;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                FoldAwareMaterialPageRoute(sourceContext: context, 
                  builder: (_) => MeridianDetailScreen(meridian: name),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              child: ExpansionTile(
                leading: Icon(meridianIcon(name), size: 28, color: color),
                title: Text(
                  '$name病',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      '${details['nature']} · ${details['organ']}',
                      style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '核心脉证：${details['keyPulse']}',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: context.colors.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '欲解时：$healingTime',
                            style: TextStyle(fontSize: 10, color: context.colors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 核心症状
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: (details['coreSymptoms'] as List<String>)
                              .map((s) => Chip(
                                    label: Text(s, style: const TextStyle(fontSize: 12)),
                                    backgroundColor: context.colors.meridianContainer(name),
                                    side: BorderSide(color: context.colors.outlineVariant),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 10),
                        // 常用方剂
                        Text('常用方剂 (${formulas.length})',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: formulas
                              .map((f) => ActionChip(
                                    label: Text(f, style: const TextStyle(fontSize: 12)),
                                    onPressed: () {
                                      final formula = FormulaRepository.getByName(f);
                                      if (formula != null) {
                                        Navigator.push(
                                          context,
                                          FoldAwareMaterialPageRoute(sourceContext: context, 
                                            builder: (_) => FormulaDetailScreen(formula: formula),
                                          ),
                                        );
                                      }
                                    },
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        // 查看详情按钮
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                FoldAwareMaterialPageRoute(sourceContext: context, 
                                  builder: (_) => MeridianDetailScreen(meridian: name),
                                ),
                              );
                            },
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            label: const Text('查看详情', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FormulaTab extends StatefulWidget {
  @override
  State<_FormulaTab> createState() => _FormulaTabState();
}

class _FormulaTabState extends State<_FormulaTab> {
  String _selectedMeridian = '全部';
  String _selectedCategory = '全部';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedFormulaId;

  static const _meridians = [
    '全部', '太阳', '阳明', '少阳', '太阴', '少阴', '厥阴'
  ];

  static const _categories = [
    '全部', '金疮药', '倪海厦经验方',
    '解表剂', '和解剂', '清热剂', '泻下剂',
    '温里剂', '补益剂', '理气剂', '活血化瘀剂',
    '祛湿剂', '化痰剂', '寒热并用剂', '外用剂',
    '祛风剂', '安神剂', '止血剂', '驱虫剂',
  ];

  // 过滤结果缓存：build 会在主题切换、tab 重入、每次输入时被调用，
  // 257 首方剂 × 四个字段 toLowerCase 全表扫描没必要反复做。
  String? _cacheKey;
  List<Formula> _cachedList = const [];

  List<Formula> _getFormulas() {
    final key = '$_selectedMeridian|$_selectedCategory|$_searchQuery';
    if (key == _cacheKey) return _cachedList;

    var list = FormulaRepository.getAll();
    if (_selectedMeridian != '全部') {
      list = list.where((f) => f.meridian.contains(_selectedMeridian)).toList();
    }
    if (_selectedCategory != '全部') {
      list = list.where((f) => f.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((f) =>
          f.name.toLowerCase().contains(q) ||
          f.indication.toLowerCase().contains(q) ||
          f.components.any((c) => c.name.toLowerCase().contains(q)) ||
          f.keywords.any((k) => k.toLowerCase().contains(q))
      ).toList();
    }
    _cacheKey = key;
    _cachedList = list;
    return list;
  }

  Widget _buildFormulaPreviewPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.medication_outlined, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('选择一首方剂', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '在左侧筛选并选择条目，右侧显示内容摘要',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaPreview(BuildContext context, Formula formula) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text(formula.meridian)),
              Chip(label: Text(formula.category)),
            ],
          ),
          const SizedBox(height: 8),
          Text(formula.name, style: Theme.of(context).textTheme.titleLarge),
          if (formula.alias.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(formula.alias, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          const Divider(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('适应证', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  SelectableText(formula.indication, style: const TextStyle(height: 1.6)),
                  const SizedBox(height: 18),
                  Text('组成', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  ...formula.components.map(
                    (component) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        [
                          component.name,
                          if (component.dosage.isNotEmpty) component.dosage,
                          if (component.role.isNotEmpty) component.role,
                        ].join(' · '),
                      ),
                    ),
                  ),
                  if (formula.dosage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('剂量资料', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SelectableText(formula.dosage),
                  ],
                  if (formula.contraindication.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('禁忌资料', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SelectableText(formula.contraindication),
                  ],
                  if (formula.explanation.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('说明', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SelectableText(formula.explanation, style: const TextStyle(height: 1.6)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                FoldAwareMaterialPageRoute(sourceContext: context, 
                  builder: (_) => FormulaDetailScreen(formula: formula),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('打开完整详情'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formulas = _getFormulas();
    Formula? selectedFormula;
    for (final formula in formulas) {
      if (formula.id == _selectedFormulaId) {
        selectedFormula = formula;
        break;
      }
    }

    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索方剂名、适应证、药物组成...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedFormulaId = null;
                        });
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => setState(() {
              _searchQuery = v.trim();
              _selectedFormulaId = null;
            }),
          ),
        ),
        // 六经筛选
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _meridians.length,
            itemBuilder: (context, index) {
              final m = _meridians[index];
              final selected = m == _selectedMeridian;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(m, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _selectedMeridian = m;
                    _selectedFormulaId = null;
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),
        // 分类筛选
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final c = _categories[index];
              final selected = c == _selectedCategory;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(c, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _selectedCategory = c;
                    _selectedFormulaId = null;
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '共 ${formulas.length} 首方剂',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useMasterDetail =
                  constraints.maxWidth >= AdaptiveMasterDetail.compactBreakpoint;
              return AdaptiveMasterDetail(
                master: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: formulas.length,
                  itemBuilder: (context, index) {
                    final formula = formulas[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        selected: useMasterDetail &&
                            formula.id == _selectedFormulaId,
                        title: Text(
                          formula.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${formula.meridian} · ${formula.category}\n${formula.indication.length > 40 ? '${formula.indication.substring(0, 40)}...' : formula.indication}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (useMasterDetail) {
                            setState(() => _selectedFormulaId = formula.id);
                          } else {
                            Navigator.push(
                              context,
                              FoldAwareMaterialPageRoute(sourceContext: context, 
                                builder: (_) => FormulaDetailScreen(formula: formula),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
                detail: selectedFormula == null
                    ? _buildFormulaPreviewPlaceholder(context)
                    : _buildFormulaPreview(context, selectedFormula),
                masterWidthFactor: 0.4,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HerbTab extends StatefulWidget {
  @override
  State<_HerbTab> createState() => _HerbTabState();
}

class _HerbTabState extends State<_HerbTab> {
  String _selectedCategory = '全部';
  String _selectedNature = '全部';
  String _selectedMeridian = '全部';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedHerbName;

  static const _meridians = [
    '全部', '肺', '心', '肝', '脾', '肾', '胃', '胆', '大肠', '小肠', '膀胱', '三焦'
  ];

  // 同 _FormulaTab：过滤结果缓存，避免每次 build 重跑全表匹配。
  String? _cacheKey;
  List<Herb> _cachedList = const [];

  List<Herb> _getHerbs() {
    final key =
        '$_selectedCategory|$_selectedNature|$_selectedMeridian|$_searchQuery';
    if (key == _cacheKey) return _cachedList;

    var herbs = HerbRepository.getAll();
    if (_selectedCategory != '全部') {
      herbs = herbs.where((h) => h.category == _selectedCategory).toList();
    }
    if (_selectedNature != '全部') {
      herbs = herbs.where((h) => h.natureCategory == _selectedNature).toList();
    }
    if (_selectedMeridian != '全部') {
      herbs = herbs.where((h) => h.meridians.contains(_selectedMeridian)).toList();
    }
    if (_searchQuery.isNotEmpty) {
      // 走 HerbRepository.matchesQuery（含异名归一）。
      // 此前此处自行拼字符串匹配，漏了 canonicalOf，导致 103 个异名中 74 个在此页搜不到
      //（例：茈胡 → 应命中柴胡）。禁止改回本地匹配。
      herbs = herbs.where((h) => HerbRepository.matchesQuery(h, _searchQuery)).toList();
    }
    _cacheKey = key;
    _cachedList = herbs;
    return herbs;
  }

  Widget _buildHerbPreviewPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.eco_outlined, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('选择一味本草', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '在左侧筛选并选择条目，右侧显示内容摘要',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildHerbPreview(BuildContext context, Herb herb) {
    Widget section(String title, String? value) {
      if (value == null || value.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SelectableText(value, style: const TextStyle(height: 1.6)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text(herb.category)),
              Chip(label: Text('性类：${herb.natureCategory}')),
              if (herb.flavor.isNotEmpty) Chip(label: Text('味：${herb.flavor}')),
              if (herb.meridians.isNotEmpty)
                Chip(label: Text('归经：${herb.meridians.join(" ")}')),
            ],
          ),
          const SizedBox(height: 8),
          Text(herb.name, style: Theme.of(context).textTheme.titleLarge),
          const Divider(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  section('主治与功效', herb.action),
                  section('性味', herb.nature),
                  section('本经原文', herb.original),
                  section('倪注', herb.niNote),
                  section('容川注', herb.rongchuan),
                  section('用量资料', herb.dosage),
                  section('禁忌资料', herb.contraindication),
                  section('临床资料', herb.clinicalNotes),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                FoldAwareMaterialPageRoute(sourceContext: context, 
                  builder: (_) => HerbDetailScreen(herb: herb),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('打开完整详情'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final herbs = _getHerbs();
    Herb? selectedHerb;
    for (final herb in herbs) {
      if (herb.name == _selectedHerbName) {
        selectedHerb = herb;
        break;
      }
    }
    final categories = HerbRepository.getCategories();
    final natures = HerbRepository.getNatureCategories();

    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索药名、功效、性味、分类...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedHerbName = null;
                        });
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => setState(() {
              _searchQuery = v.trim();
              _selectedHerbName = null;
            }),
          ),
        ),
        // Category filter
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final selected = cat == _selectedCategory;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _selectedCategory = cat;
                    _selectedHerbName = null;
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),
        // Nature + Meridian filter
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: natures.length + _meridians.length,
            itemBuilder: (context, index) {
              if (index < natures.length) {
                final n = natures[index];
                final selected = n == _selectedNature && _selectedMeridian == '全部';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(n, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _selectedNature = n;
                      _selectedMeridian = '全部';
                      _selectedHerbName = null;
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              } else {
                final m = _meridians[index - natures.length];
                final selected = m == _selectedMeridian;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(m, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _selectedMeridian = m;
                      _selectedNature = '全部';
                      _selectedHerbName = null;
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }
            },
          ),
        ),
        // Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '共 ${herbs.length} 味药',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        // 本草列表与详情摘要
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useMasterDetail =
                  constraints.maxWidth >= AdaptiveMasterDetail.compactBreakpoint;
              return AdaptiveMasterDetail(
                master: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: herbs.length,
                  itemBuilder: (context, index) {
                    final herb = herbs[index];
                    final action = herb.action ?? '';
                    final actionShort = action.length > 40
                        ? '${action.substring(0, 40)}...'
                        : action;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        selected: useMasterDetail &&
                            herb.name == _selectedHerbName,
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            herb.name.substring(0, 1),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              herb.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            Icon(herb.natureIcon, size: 14),
                          ],
                        ),
                        subtitle: Text(
                          '${herb.flavor.isNotEmpty ? "味${herb.flavor} " : ""}'
                          '${herb.meridians.isNotEmpty ? "归${herb.meridians.join(" ")} " : ""}'
                          '${herb.category}\n$actionShort',
                          style: const TextStyle(fontSize: 12),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          if (useMasterDetail) {
                            setState(() => _selectedHerbName = herb.name);
                          } else {
                            Navigator.push(
                              context,
                              FoldAwareMaterialPageRoute(sourceContext: context, 
                                builder: (_) => HerbDetailScreen(herb: herb),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
                detail: selectedHerb == null
                    ? _buildHerbPreviewPlaceholder(context)
                    : _buildHerbPreview(context, selectedHerb),
                masterWidthFactor: 0.4,
              );
            },
          ),
        ),
      ],
    );
  }
}
