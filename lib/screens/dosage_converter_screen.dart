import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/dosage_conversion_service.dart';

class DosageConverterScreen extends StatefulWidget {
  const DosageConverterScreen({super.key, this.returnResultOnComplete = false});

  final bool returnResultOnComplete;

  @override
  State<DosageConverterScreen> createState() => _DosageConverterScreenState();
}

class _DosageConverterScreenState extends State<DosageConverterScreen> {
  // 0=汉制, 1=台制, 2=唐制
  int _standard = 0;
  String _unit = '两';
  final TextEditingController _inputController = TextEditingController(text: '1');

  static const _standards = DosageConversionService.standardLabels;
  static const _weightUnits = DosageConversionService.weightUnits;
  static const _volumeUnits = DosageConversionService.volumeUnits;
  static const _lengthUnits = DosageConversionService.lengthUnits;

  // 特殊药物容积→重量（一升=X克）——数据来源：倪海厦人纪讲义·伤寒论度量衡
  static const _specialVolumeToWeight = [
    ['半夏', '一升', '130g'],
    ['蜀椒', '一升', '50g'],
    ['吴茱萸', '一升', '50g'],
    ['五味子', '一升', '50g'],
    ['虻虫', '一升', '16g'],
    ['葶苈子', '一升', '60g'],
  ];

  // 特殊药物枚数→重量——数据来源：倪海厦人纪讲义·伤寒论度量衡
  static const _specialCountToWeight = [
    ['附子（大者）', '1枚', '20~30g'],
    ['附子（中者）', '1枚', '15g'],
    ['强乌头（小者）', '1枚', '3g'],
    ['强乌头（大者）', '1枚', '5~6g'],
    ['杏仁（大者）', '10枚', '4g'],
    ['枳实', '1枚', '14.4g'],
    ['瓜蒌', '1枚', '46g'],
    ['栀子', '10枚', '15g'],
    ['石膏（鸡蛋大）', '1枚', '约40g'],
    ['厚朴', '1尺', '约30g'],
    ['竹叶', '一握', '约12g'],
  ];

  String _convert() => DosageConversionService.formatInput(
        input: _inputController.text,
        unit: _unit,
        standard: DosageConversionService.standardIds[_standard],
      );

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final result = _convert();

    return Scaffold(
      appBar: AppBar(
        title: const Text('经方剂量换算器'),
        actions: [
          if (widget.returnResultOnComplete)
            IconButton(
              tooltip: '返回 AI 助手',
              icon: const Icon(Icons.reply),
              onPressed: () => Navigator.pop(
                context,
                [
                  '经方度量衡换算结果',
                  '标准：${_standards[_standard]}',
                  '输入：${_inputController.text} $_unit',
                  '换算：${_convert()}',
                  '说明：这是单位换算，不构成临床剂量或用药建议。',
                ].join('\n'),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 度量标准选择
          Text('度量标准', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: _standards.asMap().entries.map((e) {
              return ButtonSegment<int>(value: e.key, label: Text(e.value));
            }).toList(),
            selected: {_standard},
            onSelectionChanged: (s) => setState(() => _standard = s.first),
          ),
          const SizedBox(height: 16),

          // 输入区
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _inputController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '数值',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: const InputDecoration(
                    labelText: '单位',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(enabled: false, child: Text('── 重量 ──', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant))),
                    ..._weightUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))),
                    DropdownMenuItem(enabled: false, child: Text('── 容量 ──', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant))),
                    ..._volumeUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))),
                    DropdownMenuItem(enabled: false, child: Text('── 长度 ──', style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant))),
                    ..._lengthUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _unit = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 换算结果
          Card(
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '${_inputController.text} $_unit',
                    style: TextStyle(fontSize: 16, color: colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.arrow_downward, size: 20),
                  const SizedBox(height: 4),
                  Text(
                    result,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_standards[_standard]}标准',
                    style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 常用药物特殊换算（容积→重量）
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.science),
              title: const Text('药物特殊换算（容积→重量）'),
              subtitle: const Text('一升药物的实际重量'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(1.5),
                    },
                    children: [
                      const TableRow(children: [
                        Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('药物', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('容积', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('重量', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ]),
                      ..._specialVolumeToWeight.map((row) => TableRow(
                        children: row.map((cell) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(cell, style: const TextStyle(fontSize: 12)),
                        )).toList(),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 常用药物特殊换算（枚数→重量）
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.medication),
              title: const Text('药物特殊换算（枚数→重量）'),
              subtitle: const Text('以枚/个计的药物重量'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(1.5),
                    },
                    children: [
                      const TableRow(children: [
                        Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('药物', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('数量', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('重量', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ]),
                      ..._specialCountToWeight.map((row) => TableRow(
                        children: row.map((cell) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(cell, style: const TextStyle(fontSize: 12)),
                        )).toList(),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 换算常数参考
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('换算常数参考'),
              subtitle: const Text('三套度量衡标准对照'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSection('重量', [
                        '汉制：1石=29760g, 1斤=16两=248g, 1两=24铢=15.625g, 1铢=0.65g',
                        '台制：1斤=600g, 1两=10钱=37.5g, 1钱=10分=3.75g',
                        '唐制：1斤=220g, 1两≈13.75g（范吉平《经方剂量揭秘》）',
                      ]),
                      const SizedBox(height: 8),
                      _buildSection('容量', [
                        '1升=200ml, 1合=20ml, 1撮=2ml, 1圭=0.5ml',
                      ]),
                      const SizedBox(height: 8),
                      _buildSection('长度', [
                        '1尺=23.1cm, 1寸=2.31cm',
                      ]),
                      const SizedBox(height: 8),
                      _buildSection('剂量参考（倪海厦）', [
                        '胖子：五钱起',
                        '普通人：三钱',
                        '小孩：半钱~一钱',
                        '甘草：病久五钱，刚得病二钱',
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        ...lines.map((l) => Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text(l, style: const TextStyle(fontSize: 12)),
        )),
      ],
    );
  }
}
