abstract class ReportUpdate {}

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

class RiskFactors {
  final Map<String, bool?> proxy;
  final Map<String, bool?> vpn;
  final Map<String, bool?> tor;
  final Map<String, bool?> server;
  final Map<String, bool?> abuser;
  final Map<String, bool?> robot;
  final Map<String, String?> region;

  RiskFactors({
    required this.proxy,
    required this.vpn,
    required this.tor,
    required this.server,
    required this.abuser,
    required this.robot,
    required this.region,
  });
}

class MediaUnlockInfo {
  final String name;
  final String status;
  final String region;
  final String? unlockType;

  MediaUnlockInfo({
    required this.name,
    required this.status,
    this.region = "",
    this.unlockType,
  });
}

class BasicInfoUpdate extends ReportUpdate {
  final BasicInfo basicInfo;
  BasicInfoUpdate(this.basicInfo);
}

class MediaUnlockUpdate extends ReportUpdate {
  final List<MediaUnlockInfo> mediaUnlockInfos;
  MediaUnlockUpdate(this.mediaUnlockInfos);
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
