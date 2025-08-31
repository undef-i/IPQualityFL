// 文件 1/3: lib/models/ip_report.dart

// 基础信息模型
class BasicInfo {
  final String ipAddress;
  final String asn;
  final String organization;
  final String? dmsLocation;
  final String? mapUrl;
  final String cityInfo;
  final String actualRegionInfo;
  final String registeredRegionInfo;
  final String timezone;
  final String ipType;

  BasicInfo({
    required this.ipAddress,
    required this.asn,
    required this.organization,
    this.dmsLocation,
    this.mapUrl,
    required this.cityInfo,
    required this.actualRegionInfo,
    required this.registeredRegionInfo,
    required this.timezone,
    required this.ipType,
  });
}

// 风险评分模型
class RiskScore {
  final int score;
  final String level;
  final bool fetchedSuccessfully;

  RiskScore({
    required this.score,
    required this.level,
    this.fetchedSuccessfully = true,
  });

  factory RiskScore.failed() {
    return RiskScore(
      score: 0,
      level: '获取失败',
      fetchedSuccessfully: false,
    );
  }
}

// 风险因子模型
class RiskFactors {
  final Map<String, bool?> proxy;
  final Map<String, bool?> vpn;
  final Map<String, bool?> tor;
  final Map<String, bool?> server;
  final Map<String, bool?> abuser;
  final Map<String, bool?> robot;

  RiskFactors({
    required this.proxy,
    required this.vpn,
    required this.tor,
    required this.server,
    required this.abuser,
    required this.robot,
  });
}

// 流媒体解锁信息模型 (已扩展)
class MediaUnlockInfo {
  final String name;
  final String status; // '解锁', '仅自制', '屏蔽', '失败' 等
  final String region;
  final String type;   // '原生', 'DNS' 等

  MediaUnlockInfo({
    required this.name,
    required this.status,
    this.region = "",
    this.type = "原生",
  });
}

// Stream的更新事件模型
abstract class ReportUpdate {}

class BasicInfoUpdate extends ReportUpdate {
  final BasicInfo basicInfo;
  BasicInfoUpdate(this.basicInfo);
}

class IpTypesUpdate extends ReportUpdate {
  final Map<String, String> ipTypes;
  IpTypesUpdate(this.ipTypes);
}

class RiskScoresUpdate extends ReportUpdate {
  final Map<String, RiskScore> riskScores;
  RiskScoresUpdate(this.riskScores);
}

class RiskFactorsUpdate extends ReportUpdate {
  final RiskFactors riskFactors;
  RiskFactorsUpdate(this.riskFactors);
}

class MediaUnlockUpdate extends ReportUpdate {
  final List<MediaUnlockInfo> mediaUnlockInfos;
  MediaUnlockUpdate(this.mediaUnlockInfos);
}