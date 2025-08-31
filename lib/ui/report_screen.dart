// 文件 3/3: lib/ui/report_screen.dart

import 'package:flutter/material.dart';
import '../services/report_service.dart';
import '../models/ip_report.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({Key? key}) : super(key: key);
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final ReportService _reportService = ReportService();
  late Stream<ReportUpdate> _reportStream;

  BasicInfo? _basicInfo;
  Map<String, String>? _ipTypes;
  Map<String, RiskScore>? _riskScores;
  RiskFactors? _riskFactors;
  List<MediaUnlockInfo>? _mediaInfos;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _reportStream = _reportService.streamReport();
  }

  Future<void> _refreshReport() async {
    setState(() {
      _basicInfo = null;
      _ipTypes = null;
      _riskScores = null;
      _riskFactors = null;
      _mediaInfos = null;
      _reportStream = _reportService.streamReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IP 质量报告'), centerTitle: true),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _refreshReport,
        child: StreamBuilder<ReportUpdate>(
          stream: _reportStream,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final update = snapshot.data!;
              if (update is BasicInfoUpdate) {
                _basicInfo = update.basicInfo;
              } else if (update is IpTypesUpdate) {
                _ipTypes = update.ipTypes;
              } else if (update is RiskScoresUpdate) {
                _riskScores = update.riskScores;
              } else if (update is RiskFactorsUpdate) {
                _riskFactors = update.riskFactors;
              } else if (update is MediaUnlockUpdate) {
                _mediaInfos = update.mediaUnlockInfos;
              }
            }

            if (snapshot.connectionState == ConnectionState.done && _basicInfo == null) {
              return Center(child: Text(snapshot.error?.toString() ?? '加载报告失败，请下拉重试'));
            }

            final loadedWidgets = <Widget>[
              if (_basicInfo != null) _buildIpAddressCard(context, _basicInfo!.ipAddress, _basicInfo!.ipType),
              if (_basicInfo != null) _buildBasicInfoCard(context, _basicInfo!),
              if (_mediaInfos != null) _buildMediaCard(context, _mediaInfos!),
              if (_ipTypes != null) _buildIpTypeCard(context, _ipTypes!),
              if (_riskScores != null) _buildRiskScoreCard(context, _riskScores!),
              if (_riskFactors != null) _buildRiskFactorCard(context, _riskFactors!),
              if (snapshot.connectionState == ConnectionState.active)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ];

            return ListView.separated(
              padding: const EdgeInsets.all(12.0),
              itemCount: loadedWidgets.length,
              itemBuilder: (context, index) => loadedWidgets[index],
              separatorBuilder: (context, index) => const SizedBox(height: 12),
            );
          },
        ),
      ),
    );
  }

  Widget _buildIpAddressCard(BuildContext context, String ipAddress, String ipType) {
    final bool isNative = ipType == '原生IP';
    return Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('IP 地址', style: TextStyle(fontSize: 16)), const SizedBox(height: 4),
          Text(ipAddress, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.1), softWrap: true),
        ])),
        const SizedBox(width: 16),
        Chip(label: Text(ipType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: isNative ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2), side: BorderSide.none,
        ),
      ]),
    ));
  }
  
  Widget _buildBasicInfoCard(BuildContext context, BasicInfo info) {
    return Card(elevation: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('基础信息', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      ListTile(leading: const Icon(Icons.dns_rounded), title: const Text('自治系统'), subtitle: Text('${info.asn} - ${info.organization}')),
      const Divider(height: 1, indent: 16, endIndent: 16),
      ListTile(leading: const Icon(Icons.public_rounded), title: const Text('使用地'), subtitle: Text(info.actualRegionInfo)),
      if (info.actualRegionInfo != info.registeredRegionInfo && info.registeredRegionInfo.isNotEmpty && !info.registeredRegionInfo.contains("N/A"))
        ListTile(leading: const SizedBox(width: 24), title: const Text('注册地'), subtitle: Text(info.registeredRegionInfo)),
      ListTile(leading: const Icon(Icons.location_city_rounded), title: const Text('城市 / 时区'),
        subtitle: Text('${info.cityInfo.isEmpty ? "未知" : info.cityInfo} / ${info.timezone}'),
      ),
      if (info.dmsLocation != null && info.dmsLocation != "N/A")
        ListTile(leading: const Icon(Icons.map_outlined), title: const Text('坐标'), subtitle: Text(info.dmsLocation!)),
    ]));
  }

  Widget _buildIpTypeCard(BuildContext context, Map<String, String> ipTypes) {
    final filteredTypes = Map.fromEntries(ipTypes.entries.where((e) => e.value != 'N/A' && e.value.isNotEmpty));
    if (filteredTypes.isEmpty) return const SizedBox.shrink();
    return Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('IP 使用类型', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
        Wrap(spacing: 8.0, runSpacing: 8.0,
          children: filteredTypes.entries.map((entry) {
            return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
              child: RichText(text: TextSpan(style: DefaultTextStyle.of(context).style,
                children: <TextSpan>[
                  TextSpan(text: '${entry.key}: ', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7))),
                  TextSpan(text: entry.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              )),
            );
          }).toList(),
        ),
      ]),
    ));
  }

  Widget _buildRiskScoreCard(BuildContext context, Map<String, RiskScore> scores) {
     final filteredScores = Map.fromEntries(scores.entries.where((e) => e.value.fetchedSuccessfully));
     if (filteredScores.isEmpty) return const SizedBox.shrink();
    return Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('风险评分', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
        for (var entry in filteredScores.entries)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(children: [
              SizedBox(width: 120, child: Text(entry.key, style: const TextStyle(fontStyle: FontStyle.italic))),
              Expanded(child: Tooltip(message: '分数: ${entry.value.score} | 等级: ${entry.value.level}',
                child: LinearProgressIndicator(value: entry.value.score / 100.0, minHeight: 8, borderRadius: BorderRadius.circular(4),
                  backgroundColor: Colors.grey.shade300,
                  color: entry.value.score > 75 ? Colors.red.shade600 : (entry.value.score > 40 ? Colors.orange.shade600 : Colors.green.shade600),
                ),
              )),
            ]),
          )
      ]),
    ));
  }

  Widget _buildRiskFactorCard(BuildContext context, RiskFactors factors) {
    Widget buildFactorRow(String title, Map<String, bool?> data) {
      if (data.values.every((v) => v != true)) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 60, child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
          Expanded(child: Wrap(spacing: 2.0, runSpacing: 4.0,
            children: data.entries.map((entry) {
              return Tooltip(message: entry.key, child: _getFactorIcon(entry.value));
            }).toList(),
          )),
        ]),
      );
    }
    final allRows = [
      buildFactorRow('代理', factors.proxy), buildFactorRow('VPN', factors.vpn),
      buildFactorRow('Tor', factors.tor), buildFactorRow('服务器', factors.server),
      buildFactorRow('滥用', factors.abuser), buildFactorRow('机器人', factors.robot),
    ];
    final visibleRows = allRows.where((w) => w is! SizedBox).toList();
    if (visibleRows.isEmpty) return const SizedBox.shrink();
    
    return Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('风险因子', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Row(children: [_getFactorIcon(true), const SizedBox(width: 4), const Text("是")]),
          Row(children: [_getFactorIcon(false), const SizedBox(width: 4), const Text("否")]),
          Row(children: [_getFactorIcon(null), const SizedBox(width: 4), const Text("N/A")]),
        ]),
        const Divider(height: 20),
        ...visibleRows,
      ]),
    ));
  }
  
  Widget _buildMediaCard(BuildContext context, List<MediaUnlockInfo> infos) {
    if (infos.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('流媒体解锁检测', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: infos.map((info) => Chip(
                avatar: Icon(
                  info.unlocked ? Icons.check_circle : Icons.cancel,
                  color: info.unlocked ? Colors.green : Colors.red,
                  size: 18,
                ),
                label: Text(info.region.isNotEmpty ? '${info.name} (${info.region})' : info.name, style: const TextStyle(fontSize: 13)),
              )).toList(),
            )
          ],
        ),
      ),
    );
  }

  Icon _getFactorIcon(bool? value) {
    if (value == null) {
      return Icon(Icons.remove_circle_outline, color: Colors.grey.shade500, size: 20);
    }
    return value ? Icon(Icons.check_circle, color: Colors.red.shade400, size: 20)
        : Icon(Icons.cancel_outlined, color: Colors.green.shade500, size: 20);
  }
}