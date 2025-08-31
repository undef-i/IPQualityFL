import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/ip_report.dart';
import '../services/report_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({Key? key}) : super(key: key);
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final ReportService _reportService = ReportService();

  BasicInfo? _basicInfo;
  Map<String, String>? _ipTypes;
  Map<String, RiskScore>? _riskScores;
  RiskFactors? _riskFactors;
  List<MediaUnlockInfo>? _mediaInfos;

  bool _isLoadingBasic = true;
  bool _isLoadingMedia = true;
  bool _isLoadingIpTypes = true;
  bool _isLoadingRiskScores = true;
  bool _isLoadingRiskFactors = true;

  Map<String, String> _countryNames = {};

  @override
  void initState() {
    super.initState();

    _loadCountryNames().then((_) {
      _loadAllReports();
    });
  }

  Future<void> _loadCountryNames() async {
    try {
      final String response =
          await rootBundle.loadString('assets/countries.json');
      final List<dynamic> data = json.decode(response);
      final Map<String, String> loadedNames = {};
      for (var item in data) {
        if (item is Map<String, dynamic> &&
            item['ISO2'] != null &&
            item['China'] != null) {
          loadedNames[item['ISO2']] = item['China'].trim();
        }
      }
      if (mounted) {
        setState(() {
          _countryNames = loadedNames;
        });
      }
    } catch (e) {
      print("Error loading country names: $e");
    }
  }

  @override
  void dispose() {
    _reportService.dispose();
    super.dispose();
  }

  Future<void> _loadAllReports({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _basicInfo = null;
        _mediaInfos = null;
        _ipTypes = null;
        _riskScores = null;
        _riskFactors = null;
      });
    }

    setState(() {
      _isLoadingMedia = true;
      _isLoadingIpTypes = true;
      _isLoadingRiskScores = true;
      _isLoadingRiskFactors = true;
    });

    await _loadBasicInfo();

    if (mounted && _basicInfo != null) {
      final ip = _basicInfo!.ipAddress;
      _loadMediaInfo(ip);
      _loadIpTypes(ip);
      _loadRiskScores(ip);
      _loadRiskFactors(ip);
    }
  }

  Future<void> _loadBasicInfo() async {
    if (!mounted) return;
    setState(() => _isLoadingBasic = true);

    while (_basicInfo == null && mounted) {
      try {
        await _reportService.init();
        final newIp = await _reportService.getPublicIp();
        final result = await _reportService.fetchBasicInfo(newIp);
        if (mounted) {
          setState(() {
            _basicInfo = result;
            _isLoadingBasic = false;
          });
        }
      } catch (e) {
        print("Failed to load basic info, retrying in 3 seconds... Error: $e");
        if (mounted) {
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    }
  }

  Future<void> _loadMediaInfo(String ip) async {
    if (!mounted || _basicInfo == null) return;
    final ipCountryCode = _basicInfo!.actualRegionInfo.substring(1, 3);
    setState(() => _isLoadingMedia = true);
    try {
      final result =
          await _reportService.fetchMediaUnlockInfo(ip, ipCountryCode);
      if (!mounted) return;
      setState(() => _mediaInfos = result);
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

  Future<void> _loadIpTypes(String ip) async {
    if (!mounted) return;
    setState(() => _isLoadingIpTypes = true);
    try {
      final result = await _reportService.fetchIpTypes(ip);
      if (!mounted) return;
      setState(() => _ipTypes = result);
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isLoadingIpTypes = false);
    }
  }

  Future<void> _loadRiskScores(String ip) async {
    if (!mounted) return;
    setState(() => _isLoadingRiskScores = true);
    try {
      final result = await _reportService.fetchRiskScores(ip);
      if (!mounted) return;
      setState(() => _riskScores = result);
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isLoadingRiskScores = false);
    }
  }

  Future<void> _loadRiskFactors(String ip) async {
    if (!mounted) return;
    setState(() => _isLoadingRiskFactors = true);
    try {
      final result = await _reportService.fetchRiskFactors(ip);
      if (!mounted) return;
      setState(() => _riskFactors = result);
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isLoadingRiskFactors = false);
    }
  }

  Widget _buildCardContent(
      {required bool isLoading,
      required bool hasData,
      required Widget Function() contentBuilder,
      String noDataText = '无可用数据'}) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (hasData) {
      return contentBuilder();
    } else {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Text(noDataText, style: const TextStyle(color: Colors.grey)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
              child: AppBar(
                title: const Text('IP 质量检测'),
                centerTitle: false,
                backgroundColor: Colors.transparent,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          _buildBasicInfoCard(),
          const SizedBox(height: 12),
          _buildMediaCard(),
          const SizedBox(height: 12),
          _buildIpTypeCard(),
          const SizedBox(height: 12),
          _buildRiskScoreCard(),
          const SizedBox(height: 12),
          _buildRiskFactorCard(),
        ],
      ),
    );
  }

  Widget _buildCardHeader(
      String title, bool isLoading, VoidCallback? onRefresh) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: isLoading || onRefresh == null ? null : onRefresh,
            tooltip: '重新加载此部分',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader('基础信息', _isLoadingBasic,
              _basicInfo == null ? null : _loadBasicInfo),
          _buildCardContent(
              isLoading: _isLoadingBasic,
              hasData: _basicInfo != null,
              contentBuilder: () {
                final info = _basicInfo!;
                final bool isNative = info.ipType == '原生IP';
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('IP 地址',
                              style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(info.ipAddress,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.1),
                                    softWrap: true),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isNative
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  info.ipType,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isNative
                                        ? Colors.green[800]
                                        : Colors.red[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: const Icon(Icons.dns_rounded),
                        title: const Text('自治系统'),
                        subtitle: Text('${info.asn} - ${info.organization}')),
                    ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: const Icon(Icons.public_rounded),
                        title: const Text('使用地'),
                        subtitle: Text(info.actualRegionInfo)),
                    if (info.actualRegionInfo != info.registeredRegionInfo &&
                        info.registeredRegionInfo.isNotEmpty &&
                        !info.registeredRegionInfo.contains("N/A"))
                      ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          leading: const SizedBox(width: 24),
                          title: const Text('注册地'),
                          subtitle: Text(info.registeredRegionInfo)),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: const Icon(Icons.location_city_rounded),
                      title: const Text('城市 / 时区'),
                      subtitle: Text(
                          '${info.cityInfo.isEmpty ? "未知" : info.cityInfo} / ${info.timezone}'),
                    ),
                    if (info.dmsLocation != null && info.dmsLocation != "N/A")
                      ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          leading: const Icon(Icons.map_outlined),
                          title: const Text('坐标'),
                          subtitle: Text(info.dmsLocation!)),
                  ],
                );
              },
              noDataText: '正在获取 IP 信息...'),
        ],
      ),
    );
  }

  Widget _buildIpTypeCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          _buildCardHeader(
              'IP 使用类型',
              _isLoadingIpTypes,
              _basicInfo == null
                  ? null
                  : () {
                      _loadIpTypes(_basicInfo!.ipAddress);
                    }),
          _buildCardContent(
            isLoading: _isLoadingIpTypes,
            hasData: _ipTypes != null &&
                _ipTypes!.values.any((e) => e != 'N/A' && e.isNotEmpty),
            contentBuilder: () {
              final filteredTypes = Map.fromEntries(_ipTypes!.entries
                  .where((e) => e.value != 'N/A' && e.value.isNotEmpty));
              if (filteredTypes.isEmpty)
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Text('无可用数据',
                            style: TextStyle(color: Colors.grey))));
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: filteredTypes.entries.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8)),
                      child: RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodyMedium,
                          children: <TextSpan>[
                            TextSpan(
                                text: '${entry.key}: ',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7))),
                            TextSpan(
                                text: entry.value,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRiskScoreCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          _buildCardHeader(
              '风险评分',
              _isLoadingRiskScores,
              _basicInfo == null
                  ? null
                  : () {
                      _loadRiskScores(_basicInfo!.ipAddress);
                    }),
          _buildCardContent(
            isLoading: _isLoadingRiskScores,
            hasData: _riskScores != null &&
                _riskScores!.values.any((e) => e.fetchedSuccessfully),
            contentBuilder: () {
              final filteredScores = Map.fromEntries(_riskScores!.entries
                  .where((e) => e.value.fetchedSuccessfully));
              if (filteredScores.isEmpty)
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Text('无可用数据',
                            style: TextStyle(color: Colors.grey))));
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    for (var entry in filteredScores.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(children: [
                          SizedBox(
                              width: 120,
                              child: Text(entry.key, style: const TextStyle())),
                          Expanded(
                              child: Tooltip(
                            message:
                                '分数: ${entry.value.score} | 等级: ${entry.value.level}',
                            child: LinearProgressIndicator(
                              value: entry.value.score / 100.0,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                              backgroundColor: Colors.grey.shade300,
                              color: entry.value.score > 75
                                  ? Colors.red.shade600
                                  : (entry.value.score > 40
                                      ? Colors.orange.shade600
                                      : Colors.green.shade600),
                            ),
                          )),
                        ]),
                      )
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRiskFactorCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          _buildCardHeader(
              '风险因子',
              _isLoadingRiskFactors,
              _basicInfo == null
                  ? null
                  : () {
                      _loadRiskFactors(_basicInfo!.ipAddress);
                    }),
          _buildCardContent(
            isLoading: _isLoadingRiskFactors,
            hasData: _riskFactors != null,
            contentBuilder: () {
              final factors = _riskFactors!;

              Widget buildRegionRow(String title, Map<String, String?> data) {
                final validEntries = data.entries.where(
                    (entry) => entry.value != null && entry.value!.isNotEmpty);
                if (validEntries.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 60,
                          child: Text(title,
                              style: Theme.of(context).textTheme.titleSmall)),
                      Expanded(
                        child: Wrap(
                          spacing: 4.0,
                          runSpacing: 4.0,
                          children: validEntries.map((entry) {
                            final countryName = _getCountryName(entry.value!);
                            return Tooltip(
                              message: '${entry.key}: $countryName',
                              child: Text(_countryCodeToFlag(entry.value!),
                                  style: const TextStyle(fontSize: 16)),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }

              Widget buildFactorRow(String title, Map<String, bool?> data) {
                final validEntries =
                    data.entries.where((entry) => entry.value != null);
                if (validEntries.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: 60,
                            child: Text(title,
                                style: Theme.of(context).textTheme.titleSmall)),
                        Expanded(
                            child: Wrap(
                          spacing: 2.0,
                          runSpacing: 4.0,
                          children: validEntries.map((entry) {
                            return Tooltip(
                                message: entry.key,
                                child: _getFactorIcon(entry.value));
                          }).toList(),
                        )),
                      ]),
                );
              }

              final allRows = [
                buildRegionRow('地区', factors.region),
                buildFactorRow('代理', factors.proxy),
                buildFactorRow('VPN', factors.vpn),
                buildFactorRow('Tor', factors.tor),
                buildFactorRow('服务器', factors.server),
                buildFactorRow('滥用', factors.abuser),
                buildFactorRow('机器人', factors.robot),
              ];
              final visibleRows = allRows.where((w) => w is! SizedBox).toList();
              if (visibleRows.isEmpty)
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Text('未发现已知风险因子',
                            style: TextStyle(color: Colors.grey))));

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Row(children: [
                            _getFactorIcon(true),
                            const SizedBox(width: 4),
                            const Text("是")
                          ]),
                          Row(children: [
                            _getFactorIcon(false),
                            const SizedBox(width: 4),
                            const Text("否")
                          ]),
                        ]),
                    const Divider(height: 20),
                    ...visibleRows,
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMediaCard() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          _buildCardHeader(
              '流媒体与AI检测',
              _isLoadingMedia,
              _basicInfo == null
                  ? null
                  : () {
                      _loadMediaInfo(_basicInfo!.ipAddress);
                    }),
          _buildCardContent(
            isLoading: _isLoadingMedia,
            hasData: _mediaInfos != null && _mediaInfos!.isNotEmpty,
            contentBuilder: () {
              _mediaInfos!.sort((a, b) {
                int scoreA = a.status == '解锁' ? 0 : (a.status == '仅自制' ? 1 : 2);
                int scoreB = b.status == '解锁' ? 0 : (b.status == '仅自制' ? 1 : 2);
                return scoreA.compareTo(scoreB);
              });

              return Column(
                children: [
                  for (int i = 0; i < _mediaInfos!.length; i++) ...[
                    _buildMediaListItem(_mediaInfos![i]),
                    if (i < _mediaInfos!.length - 1)
                      const Divider(height: 1, indent: 56, endIndent: 16),
                  ]
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMediaListItem(MediaUnlockInfo info) {
    Color iconColor;
    IconData iconData;

    switch (info.status) {
      case '解锁':
        iconColor = Colors.green;
        iconData = Icons.check_circle;
        break;
      case '仅自制':
        iconColor = Colors.orange;
        iconData = Icons.theaters;
        break;
      case '屏蔽':
      case '不支持':
        iconColor = Colors.red;
        iconData = Icons.cancel;
        break;
      default:
        iconColor = Colors.grey;
        iconData = Icons.help_outline;
    }

    return ListTile(
      leading: Icon(iconData, color: iconColor),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${info.name}${info.region.isNotEmpty ? ' [${info.region}]' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (info.unlockType != null && info.unlockType!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
              ),
              child: Text(
                info.unlockType!,
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Icon _getFactorIcon(bool? value) {
    if (value == null) {
      return Icon(Icons.remove_circle_outline,
          color: Colors.grey.shade500, size: 20);
    }
    return value
        ? Icon(Icons.check_circle, color: Colors.red.shade400, size: 20)
        : Icon(Icons.cancel_outlined, color: Colors.green.shade500, size: 20);
  }

  String _countryCodeToFlag(String countryCode) {
    if (countryCode.length != 2) return '🏴';
    final String code = countryCode.toUpperCase();
    final int firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(firstLetter) + String.fromCharCode(secondLetter);
  }

  String _getCountryName(String code) {
    return _countryNames[code.toUpperCase()] ?? code.toUpperCase();
  }
}
