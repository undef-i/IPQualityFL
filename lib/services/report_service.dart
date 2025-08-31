import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_curl/flutter_curl.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import '../models/ip_report.dart';

class ReportService {
  final Client _curlClient = Client(verbose: false);
  final http.Client _httpClient = http.Client();
  final String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  Future<void> init() async {
    await _curlClient.init();
  }

  void dispose() {
    _curlClient.dispose();
    _httpClient.close();
  }

  Future<T?> _guardedFetch<T>(
      String apiName, Future<T> Function() fetcher) async {
    try {
      return await fetcher();
    } catch (e) {
      print('❌ [$apiName] 获取失败: $e');
      return null;
    }
  }

  Future<dynamic> _curlGetAndParse(String url) async {
    final request =
        Request(method: 'GET', url: url, headers: {'User-Agent': _ua});
    final response = await _curlClient.send(request);
    if (response.statusCode == 200) {
      if (response.body.isEmpty) throw Exception('Response body is empty.');
      return jsonDecode(response.text());
    } else {
      throw Exception('Status Code ${response.statusCode}');
    }
  }

  Future<dynamic> _fetchIpqsDataWithRedirect(String ip) async {
    final initialUrl = 'https://ipinfo.check.place/$ip?db=ipqualityscore';
    final initialRequest =
        Request(method: 'GET', url: initialUrl, headers: {'User-Agent': _ua});
    final initialResponse = await _curlClient.send(initialRequest);

    if (initialResponse.statusCode == 302) {
      final location = initialResponse.headers['location'];
      if (location == null || location.isEmpty)
        throw Exception('302 Redirect: No location header.');
      final finalRequest =
          Request(method: 'GET', url: location, headers: {'User-Agent': _ua});
      final finalResponse = await _curlClient.send(finalRequest);
      if (finalResponse.statusCode == 200) {
        if (finalResponse.body.isEmpty)
          throw Exception('Final response body is empty.');
        return jsonDecode(finalResponse.text());
      } else {
        throw Exception(
            'Redirected request failed: Status Code ${finalResponse.statusCode}');
      }
    } else if (initialResponse.statusCode == 200) {
      if (initialResponse.body.isEmpty)
        throw Exception('Initial response body is empty.');
      return jsonDecode(initialResponse.text());
    } else {
      throw Exception(
          'Initial request failed: Status Code ${initialResponse.statusCode}');
    }
  }

  Future<String> getPublicIp() async {
    final ipResponse =
        await _httpClient.get(Uri.parse('https://api.ipify.org?format=json'));
    if (ipResponse.statusCode != 200) throw Exception('获取公网IP失败');
    return jsonDecode(ipResponse.body)['ip'];
  }

  Future<BasicInfo> fetchBasicInfo(String ip) async {
    final basicInfoResults = await Future.wait([
      _guardedFetch('Maxmind', () => _fetchMaxmindData(ip)),
      _guardedFetch('IPinfo', () => _fetchIpInfoData(ip)),
      _guardedFetch('ip-api.is', () => _fetchIpApiData(ip)),
    ]);
    final maxmindData = basicInfoResults[0];
    final ipInfoData = basicInfoResults[1];
    final ipApiData = basicInfoResults[2];

    if (maxmindData == null && ipInfoData == null && ipApiData == null) {
      throw Exception('基础信息获取失败，请检查网络连接');
    }
    return _buildBasicInfo(ip, maxmindData, ipInfoData, ipApiData);
  }

  Future<List<MediaUnlockInfo>> fetchMediaUnlockInfo(
      String ip, String ipCountryCode) async {
    final mediaFutures = [
      _fetchNetflixStatus(ip, ipCountryCode),
      _fetchYoutubeStatus(ipCountryCode),
      _fetchDisneyPlusStatus(),
      _fetchChatGPTStatus(ip, ipCountryCode),
      _fetchTikTokStatus(ipCountryCode),
      _fetchAmazonPrimeStatus(ipCountryCode),
      _fetchSpotifyStatus(ipCountryCode),
      _fetchBilibiliGlobalStatus(ipCountryCode),
      _fetchHboMaxStatus(ipCountryCode),
      _fetchAbemaTvStatus(ipCountryCode),
      _fetchDaznStatus(ipCountryCode),
    ];
    return (await Future.wait(mediaFutures))
        .whereType<MediaUnlockInfo>()
        .toList();
  }

  Future<Map<String, String>> fetchIpTypes(String ip) async {
    final ipInfoData =
        await _guardedFetch('IPinfo', () => _fetchIpInfoData(ip));
    final typeDataResults = await Future.wait([
      _guardedFetch(
          'ipregistry',
          () =>
              _curlGetAndParse('https://ipinfo.check.place/$ip?db=ipregistry')),
      _guardedFetch('ip-api.is (for types)', () => _fetchIpApiData(ip)),
      _guardedFetch(
          'AbuseIPDB (for types)',
          () =>
              _curlGetAndParse('https://ipinfo.check.place/$ip?db=abuseipdb')),
      _guardedFetch(
          'IP2Location (for types)',
          () => _curlGetAndParse(
              'https://ipinfo.check.place/$ip?db=ip2location')),
    ]);
    final ipregistryData = typeDataResults[0];
    final ipApiDataForTypes = typeDataResults[1];
    final abuseIpDbDataForTypes = typeDataResults[2];
    final ip2locationForTypes = typeDataResults[3];

    return {
      'IPinfo': ipInfoData?['usageType']?.toString().toUpperCase() ?? 'N/A',
      'ipregistry':
          ipregistryData?['connection']?['type']?.toString().toUpperCase() ??
              'N/A',
      'ip-api.is':
          ipApiDataForTypes?['usageType']?.toString().toUpperCase() ?? 'N/A',
      'AbuseIPDB':
          abuseIpDbDataForTypes?['data']?['usageType']?.toString() ?? 'N/A',
      'IP2Location':
          ip2locationForTypes?['usage_type']?.toString().toUpperCase() ?? 'N/A',
    };
  }

  Future<Map<String, RiskScore>> fetchRiskScores(String ip) async {
    final scoreDataResults = await Future.wait([
      _guardedFetch(
          'IP2Location (for scores)',
          () => _curlGetAndParse(
              'https://ipinfo.check.place/$ip?db=ip2location')),
      _guardedFetch('Scamalytics', () => _fetchScamalyticsData(ip)),
      _guardedFetch('ip-api.is (for scores)', () => _fetchIpApiData(ip)),
      _guardedFetch(
          'AbuseIPDB (for scores)',
          () =>
              _curlGetAndParse('https://ipinfo.check.place/$ip?db=abuseipdb')),
      _guardedFetch('IPQS', () => _fetchIpqsDataWithRedirect(ip)),
      _guardedFetch('Cloudflare', () => _fetchCloudflareData(ip)),
      _guardedFetch('DB-IP', () => _fetchDbIpData(ip)),
    ]);
    final ip2locationForScores = scoreDataResults[0];
    final scamalyticsData = scoreDataResults[1];
    final ipApiDataForScores = scoreDataResults[2];
    final abuseIpDbDataForScores = scoreDataResults[3];
    final ipqsData = scoreDataResults[4];
    final cloudflareData = scoreDataResults[5];
    final dbipData = scoreDataResults[6];

    return {
      'IP2Location': ip2locationForScores != null
          ? RiskScore(
              score: ip2locationForScores['fraud_score'] ?? 0,
              level:
                  _getRiskLevel(ip2locationForScores['fraud_score'], [33, 66]))
          : RiskScore.failed(),
      'SCAMALYTICS':
          scamalyticsData?['score'] as RiskScore? ?? RiskScore.failed(),
      'ip-api.is':
          ipApiDataForScores?['score'] as RiskScore? ?? RiskScore.failed(),
      'AbuseIPDB': abuseIpDbDataForScores != null
          ? RiskScore(
              score:
                  abuseIpDbDataForScores['data']?['abuseConfidenceScore'] ?? 0,
              level: _getRiskLevel(
                  abuseIpDbDataForScores['data']?['abuseConfidenceScore'],
                  [25, 75]))
          : RiskScore.failed(),
      'IPQS': ipqsData != null
          ? RiskScore(
              score: ipqsData['fraud_score'] ?? 0,
              level: _getIpqsRiskLevel(ipqsData['fraud_score']))
          : RiskScore.failed(),
      'Cloudflare': cloudflareData != null
          ? RiskScore(
              score: cloudflareData['score'] ?? 0,
              level: _getRiskLevel(cloudflareData['score'], [10, 25]))
          : RiskScore.failed(),
      'DB-IP': dbipData?['score'] as RiskScore? ?? RiskScore.failed(),
    };
  }

  Future<RiskFactors> fetchRiskFactors(String ip) async {
    final results = await Future.wait([
      _guardedFetch(
          'IP2Location',
          () => _curlGetAndParse(
              'https://ipinfo.check.place/$ip?db=ip2location')),
      _guardedFetch('ip-api.is', () => _fetchIpApiData(ip)),
      _guardedFetch(
          'ipregistry',
          () =>
              _curlGetAndParse('https://ipinfo.check.place/$ip?db=ipregistry')),
      _guardedFetch('IPQS', () => _fetchIpqsDataWithRedirect(ip)),
      _guardedFetch('Scamalytics', () => _fetchScamalyticsData(ip)),
      _guardedFetch('ipdata',
          () => _curlGetAndParse('https://ipinfo.check.place/$ip?db=ipdata')),
      _guardedFetch('IPinfo', () => _fetchIpInfoData(ip)),
      _guardedFetch('IPWHOIS', () => _fetchIpWhoisData(ip)),
      _guardedFetch('DB-IP', () => _fetchDbIpData(ip)),
    ]);
    final ip2locationData = results[0];
    final ipApiData = results[1];
    final ipregistryData = results[2];
    final ipqsData = results[3];
    final scamalyticsData = results[4];
    final ipdataData = results[5];
    final ipInfoData = results[6];
    final ipwhoisData = results[7];
    final dbipData = results[8];

    final ip2locationProxy = (ip2locationData?['is_proxy'] == true ||
        (ip2locationData?['proxy']?['is_public_proxy'] == true) ||
        (ip2locationData?['proxy']?['is_web_proxy'] == true));
    final ip2locationRobot =
        (ip2locationData?['proxy']?['is_web_crawler'] == true ||
            (ip2locationData?['proxy']?['is_scanner'] == true) ||
            (ip2locationData?['proxy']?['is_botnet'] == true));
    final ipregistryTor = (ipregistryData?['security']?['is_tor'] == true ||
        (ipregistryData?['security']?['is_tor_exit'] == true));
    final ipdataAbuser = (ipdataData?['threat']?['is_threat'] == true ||
        (ipdataData?['threat']?['is_known_abuser'] == true) ||
        (ipdataData?['threat']?['is_known_attacker'] == true));

    return RiskFactors(
      proxy: {
        'IP2Location': ip2locationProxy,
        'ip-api.is': ipApiData?['proxy'],
        'ipregistry': ipregistryData?['security']?['is_proxy'],
        'IPQS': ipqsData?['proxy'],
        'SCAMALYTICS': scamalyticsData?['proxy'],
        'ipdata': ipdataData?['threat']?['is_proxy'],
        'IPinfo': ipInfoData?['proxy'],
        'IPWHOIS': ipwhoisData?['proxy'],
      },
      vpn: {
        'IP2Location': ip2locationData?['proxy']?['is_vpn'],
        'ip-api.is': ipApiData?['vpn'],
        'ipregistry': ipregistryData?['security']?['is_vpn'],
        'IPQS': ipqsData?['vpn'],
        'SCAMALYTICS': scamalyticsData?['vpn'],
        'IPinfo': ipInfoData?['vpn'],
        'IPWHOIS': ipwhoisData?['vpn'],
        'ipdata': null,
      },
      tor: {
        'IP2Location': ip2locationData?['proxy']?['is_tor'],
        'ip-api.is': ipApiData?['tor'],
        'ipregistry': ipregistryTor,
        'IPQS': ipqsData?['tor'],
        'SCAMALYTICS': scamalyticsData?['tor'],
        'ipdata': ipdataData?['threat']?['is_tor'],
        'IPinfo': ipInfoData?['tor'],
        'IPWHOIS': ipwhoisData?['tor'],
      },
      server: {
        'IP2Location': ip2locationData?['proxy']?['is_data_center'],
        'ip-api.is': ipApiData?['server'],
        'ipregistry': ipregistryData?['security']?['is_cloud_provider'],
        'SCAMALYTICS': scamalyticsData?['server'],
        'ipdata': ipdataData?['threat']?['is_datacenter'],
        'IPinfo': ipInfoData?['server'],
        'IPWHOIS': ipwhoisData?['server'],
      },
      abuser: {
        'IP2Location': ip2locationData?['proxy']?['is_spammer'],
        'ip-api.is': ipApiData?['abuser'],
        'ipregistry': ipregistryData?['security']?['is_abuser'],
        'IPQS': ipqsData?['recent_abuse'],
        'ipdata': ipdataAbuser,
      },
      robot: {
        'IP2Location': ip2locationRobot,
        'ip-api.is': ipApiData?['robot'],
        'IPQS': ipqsData?['bot_status'],
        'DB-IP': dbipData?['robot'],
      },
      region: {
        'IP2Location': ip2locationData?['country_code'],
        'ip-api.is': ipApiData?['countryCode'],
        'ipregistry': ipregistryData?['location']?['country']?['code'],
        'IPQS': ipqsData?['country_code'],
        'SCAMALYTICS': scamalyticsData?['countryCode'],
        'ipdata': ipdataData?['country_code'],
        'IPinfo': ipInfoData?['countryCode'],
        'IPWHOIS': ipwhoisData?['countryCode'],
        'DB-IP': dbipData?['countryCode'],
      },
    );
  }

  BasicInfo _buildBasicInfo(String ip, Map<String, dynamic>? maxmindData,
      Map<String, dynamic>? ipInfoData, Map<String, dynamic>? ipApiData) {
    if (maxmindData != null) {
      return BasicInfo(
        ipAddress: ip,
        asn: 'AS${maxmindData['asn'] ?? 'N/A'}',
        organization: maxmindData['org'] ?? '未知',
        dmsLocation: (maxmindData['lat'] != null && maxmindData['lon'] != null)
            ? _generateDms(maxmindData['lat'], maxmindData['lon'])
            : null,
        mapUrl: (maxmindData['lat'] != null && maxmindData['lon'] != null)
            ? 'https://www.google.com/maps/@${maxmindData['lat']},${maxmindData['lon']},12z'
            : null,
        cityInfo: [maxmindData['sub'], maxmindData['city']]
            .where((s) => s != null && s.isNotEmpty)
            .join(', '),
        actualRegionInfo:
            '[${maxmindData['countryCode'] ?? 'N/A'}] ${maxmindData['country'] ?? '未知'}',
        registeredRegionInfo:
            '[${maxmindData['regCountryCode'] ?? 'N/A'}] ${maxmindData['regCountry'] ?? '未知'}',
        timezone: maxmindData['timezone'] ?? '未知',
        ipType: maxmindData['countryCode'] == maxmindData['regCountryCode']
            ? '原生IP'
            : '广播IP',
      );
    } else if (ipInfoData != null) {
      return BasicInfo(
        ipAddress: ip,
        asn: ipInfoData['asn'] ?? 'N/A',
        organization: ipInfoData['org'] ?? '未知',
        dmsLocation: (ipInfoData['lat'] != null && ipInfoData['lon'] != null)
            ? _generateDms(ipInfoData['lat'], ipInfoData['lon'])
            : null,
        mapUrl: (ipInfoData['lat'] != null && ipInfoData['lon'] != null)
            ? 'https://www.google.com/maps/@${ipInfoData['lat']},${ipInfoData['lon']},12z'
            : null,
        cityInfo: [ipInfoData['regionName'], ipInfoData['city']]
            .where((s) => s != null && s.isNotEmpty)
            .join(', '),
        actualRegionInfo:
            '[${ipInfoData['countryCode'] ?? 'N/A'}] ${ipInfoData['country'] ?? '未知'}',
        registeredRegionInfo:
            '[${ipInfoData['abuseCountryCode'] ?? 'N/A'}] ${ipInfoData['abuseCountry'] ?? '未知'}',
        timezone: ipInfoData['timezone'] ?? '未知',
        ipType: ipInfoData['countryCode'] == ipInfoData['abuseCountryCode']
            ? '原生IP'
            : '广播IP',
      );
    } else if (ipApiData != null) {
      return BasicInfo(
        ipAddress: ip,
        asn: 'AS${ipApiData['asnNumber'] ?? 'N/A'}',
        organization: ipApiData['asnOrg'] ?? '未知',
        dmsLocation:
            (ipApiData['latitude'] != null && ipApiData['longitude'] != null)
                ? _generateDms(ipApiData['latitude'], ipApiData['longitude'])
                : null,
        mapUrl: (ipApiData['latitude'] != null &&
                ipApiData['longitude'] != null)
            ? 'https://www.google.com/maps/@${ipApiData['latitude']},${ipApiData['longitude']},12z'
            : null,
        cityInfo: [ipApiData['state'], ipApiData['city']]
            .where((s) => s != null && s.isNotEmpty)
            .join(', '),
        actualRegionInfo:
            '[${ipApiData['countryCode'] ?? 'N/A'}] ${ipApiData['country'] ?? '未知'}',
        registeredRegionInfo:
            '[${ipApiData['countryCode'] ?? 'N/A'}] ${ipApiData['country'] ?? '未知'}',
        timezone: ipApiData['timezone'] ?? '未知',
        ipType: '原生IP',
      );
    } else {
      return BasicInfo(
        ipAddress: ip,
        asn: '加载失败',
        organization: '加载失败',
        cityInfo: '加载失败',
        actualRegionInfo: '加载失败',
        registeredRegionInfo: '加载失败',
        timezone: '加载失败',
        ipType: '未知',
      );
    }
  }

  Future<Map<String, dynamic>> _fetchMaxmindData(String ip) async {
    final data =
        await _curlGetAndParse('https://ipinfo.check.place/$ip?lang=zh-CN');
    return {
      'asn': data['ASN']?['AutonomousSystemNumber'],
      'org': data['ASN']?['AutonomousSystemOrganization'],
      'lat': data['City']?['Latitude'],
      'lon': data['City']?['Longitude'],
      'city': data['City']?['Name'],
      'sub': data['City']?['Subdivisions']?[0]?['Name'],
      'country': data['City']?['Country']?['Name'],
      'countryCode': data['City']?['Country']?['IsoCode'],
      'regCountry': data['Country']?['RegisteredCountry']?['Name'],
      'regCountryCode': data['Country']?['RegisteredCountry']?['IsoCode'],
      'timezone': data['City']?['Location']?['TimeZone'],
    };
  }

  Future<Map<String, dynamic>> _fetchIpInfoData(String ip) async {
    final uri = Uri.parse('https://ipinfo.io/widget/demo/$ip');
    final response = await _httpClient.get(uri, headers: {'User-Agent': _ua});
    if (response.statusCode != 200)
      throw Exception('Status Code ${response.statusCode}');
    final data = jsonDecode(response.body)['data'];
    final loc = (data['loc'] as String?)?.split(',');
    return {
      'asn': data['asn']?['asn'],
      'org': data['asn']?['name'],
      'city': data['city'],
      'regionName': data['region'],
      'country': data['country'],
      'countryCode': data['country'],
      'abuseCountry': data['abuse']?['country'],
      'abuseCountryCode': data['abuse']?['country'],
      'lat': loc != null ? double.tryParse(loc[0]) : null,
      'lon': loc != null ? double.tryParse(loc[1]) : null,
      'timezone': data['timezone'],
      'usageType': data['asn']?['type'],
      'proxy': data['privacy']?['proxy'],
      'vpn': data['privacy']?['vpn'],
      'tor': data['privacy']?['tor'],
      'server': data['privacy']?['hosting'],
    };
  }

  Future<Map<String, dynamic>> _fetchScamalyticsData(String ip) async {
    final uri = Uri.parse('https://scamalytics.com/ip/$ip');
    final response = await _httpClient.get(uri, headers: {'User-Agent': _ua});
    if (response.statusCode != 200)
      throw Exception('Status Code ${response.statusCode}');
    final document = parse(response.body);
    int scoreVal = int.tryParse(document
                .querySelector('div[style*="font-size: 20px"]')
                ?.text
                .replaceAll('Fraud Score: ', '') ??
            '-1') ??
        -1;
    if (scoreVal == -1) return {'score': RiskScore.failed()};
    String? findRowValue(String label) {
      final ths = document.querySelectorAll('th');
      for (var th in ths) {
        if (th.text.trim() == label) return th.nextElementSibling?.text.trim();
      }
      return null;
    }

    bool? findFactor(String label) =>
        findRowValue(label)?.toLowerCase() == 'yes';

    final isProxy = findFactor('Public Proxy') ?? findFactor('Web Proxy');
    return {
      'score':
          RiskScore(score: scoreVal, level: _getRiskLevel(scoreVal, [25, 75])),
      'proxy': isProxy,
      'vpn': findFactor('Anonymizing VPN'),
      'tor': findFactor('Tor Exit Node'),
      'server': findFactor('Server'),
      'countryCode': findRowValue('Country Code'),
    };
  }

  Future<Map<String, dynamic>> _fetchIpApiData(String ip) async {
    final uri = Uri.parse('https://api.ipapi.is/?q=$ip');
    final response = await _httpClient.get(uri, headers: {'User-Agent': _ua});
    if (response.statusCode != 200)
      throw Exception('Status Code ${response.statusCode}');
    final data = jsonDecode(response.body);
    String scoreText = data['company']?['abuser_score_text'] ?? "0";
    double scoreDouble = double.tryParse(scoreText.split(' ')[0]) ?? 0.0;
    return {
      'usageType': data['asn']?['type'],
      'score': RiskScore(
          score: (scoreDouble * 100).toInt(),
          level: _mapIpApiRiskLevel(data['company']?['abuser_score_text'])),
      'proxy': data['is_proxy'],
      'vpn': data['is_vpn'],
      'tor': data['is_tor'],
      'server': data['is_datacenter'],
      'abuser': data['is_abuser'],
      'robot': data['is_crawler'],
      'asnNumber': data['asn']?['asn'],
      'asnOrg': data['asn']?['org'],
      'country': data['location']?['country'],
      'countryCode': data['location']?['country_code'],
      'state': data['location']?['state'],
      'city': data['location']?['city'],
      'latitude': data['location']?['latitude'],
      'longitude': data['location']?['longitude'],
      'timezone': data['location']?['timezone'],
    };
  }

  Future<Map<String, dynamic>> _fetchDbIpData(String ip) async {
    final uri = Uri.parse('https://db-ip.com/$ip');
    final response = await _httpClient.get(uri, headers: {'User-Agent': _ua});
    if (response.statusCode != 200)
      throw Exception('Status Code ${response.statusCode}');
    final document = parse(response.body);
    final threatLevelText = document
            .querySelector('.card-body .mb-1 + p > span')
            ?.text
            .toLowerCase() ??
        '';
    int score;
    String riskLevel;
    switch (threatLevelText) {
      case 'medium':
        score = 50;
        riskLevel = '中风险';
        break;
      case 'high':
        score = 80;
        riskLevel = '高风险';
        break;
      case 'very high':
        score = 100;
        riskLevel = '极高风险';
        break;
      default:
        score = 10;
        riskLevel = '低风险';
    }
    bool? findFactor(dom.Element card) {
      final value =
          card.querySelector('span.sr-only')?.text.trim().toLowerCase();
      return value == 'yes' ? true : (value == 'no' ? false : null);
    }

    final cards = document.querySelectorAll('.threat-matrix .card');
    String? countryCode;
    final scripts =
        document.querySelectorAll('script[type="application/ld+json"]');
    for (var script in scripts) {
      try {
        final jsonData = jsonDecode(script.text);
        if (jsonData['@type'] == 'WebPage') {
          final text = jsonData['mainEntity']['text'];
          final match = RegExp(r'countryCode:\s*"([A-Z]{2})"').firstMatch(text);
          if (match != null) {
            countryCode = match.group(1);
            break;
          }
        }
      } catch (e) {/* ignore json parsing errors */}
    }

    return {
      'score': RiskScore(score: score, level: riskLevel),
      'robot': cards.isNotEmpty ? findFactor(cards[0]) : null,
      'proxy': cards.length > 1 ? findFactor(cards[1]) : null,
      'countryCode': countryCode,
    };
  }

  Future<Map<String, dynamic>> _fetchCloudflareData(String ip) async {
    final uri = Uri.parse('https://ip.nodeget.com/json');
    final response = await _curlGetAndParse(uri.toString());
    return {'score': response['ip']?['riskScore']};
  }

  Future<Map<String, dynamic>> _fetchIpWhoisData(String ip) async {
    final uri = Uri.parse('https://ipwhois.io/widget?ip=$ip&lang=en');
    final response = await _httpClient.get(uri, headers: {'User-Agent': _ua});
    if (response.statusCode != 200)
      throw Exception('Status Code ${response.statusCode}');
    final data = jsonDecode(response.body);
    return {
      'proxy': data['security']?['proxy'],
      'vpn': data['security']?['vpn'],
      'tor': data['security']?['tor'],
      'server': data['security']?['hosting'],
      'asnNumber': data['asn_number'],
      'asnOrg': data['organization'],
      'country': data['country'],
      'countryCode': data['country_code'],
      'region': data['region'],
      'city': data['city'],
      'latitude': data['latitude'],
      'longitude': data['longitude'],
      'timezoneId': data['timezone']?['id'],
    };
  }

  Future<MediaUnlockInfo?> _fetchBilibiliGlobalStatus(
      String ipCountryCode) async {
    try {
      final response = await _httpClient.get(
          Uri.parse(
              'https://api.bilibili.tv/intl/gateway/web/playurl?s_locale=en_US&platform=web&ep_id=347666'),
          headers: {'User-Agent': _ua});
      final data = jsonDecode(response.body);
      if (data['code'] == 0) {
        return MediaUnlockInfo(
            name: 'Bilibili 国际',
            status: '解锁',
            region: ipCountryCode,
            unlockType: "原生");
      }
      return MediaUnlockInfo(name: 'Bilibili 国际', status: '屏蔽');
    } catch (e) {
      print('❌ [Bilibili] 获取失败: $e');
      return null;
    }
  }

  Future<MediaUnlockInfo?> _fetchHboMaxStatus(String ipCountryCode) async {
    try {
      final request = http.Request('GET', Uri.parse('https://www.max.com/'));
      request.followRedirects = false;
      request.headers['User-Agent'] = _ua;
      final response = await _httpClient.send(request);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'] ?? '';
        if (location.contains('geo-availability')) {
          return MediaUnlockInfo(name: 'HBO Max', status: '屏蔽');
        }
        final regionMatch =
            RegExp(r'https://www.max.com/([a-z]{2})/en').firstMatch(location);
        final region = regionMatch?.group(1)?.toUpperCase() ?? '';
        final unlockType =
            (region.isNotEmpty && region != ipCountryCode) ? "DNS" : "原生";
        return MediaUnlockInfo(
            name: 'HBO Max',
            status: '解锁',
            region: region,
            unlockType: unlockType);
      }
      return MediaUnlockInfo(
          name: 'HBO Max',
          status: '解锁',
          region: ipCountryCode,
          unlockType: "原生");
    } catch (e) {
      print('❌ [HBO Max] 获取失败: $e');
      return null;
    }
  }

  Future<MediaUnlockInfo?> _fetchAbemaTvStatus(String ipCountryCode) async {
    try {
      final response = await _httpClient.get(
          Uri.parse('https://api.abema.io/v1/ip/check?device=android'),
          headers: {'User-Agent': _ua});
      final data = jsonDecode(response.body);
      final region = data['isoCountryCode'] ?? '';
      if (region == 'JP') {
        final unlockType = (region != ipCountryCode) ? "DNS" : "原生";
        return MediaUnlockInfo(
            name: 'AbemaTV',
            status: '解锁',
            region: 'JP',
            unlockType: unlockType);
      }
      return MediaUnlockInfo(name: 'AbemaTV', status: '屏蔽');
    } catch (e) {
      print('❌ [AbemaTV] 获取失败: $e');
      return null;
    }
  }

  Future<MediaUnlockInfo?> _fetchDaznStatus(String ipCountryCode) async {
    try {
      final response = await _httpClient.post(
          Uri.parse('https://startup.core.indazn.com/misl/v5/Startup'),
          headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
          body: jsonEncode({
            "LandingPageKey": "generic",
            "Languages": "en",
            "Platform": "web"
          }));
      final data = jsonDecode(response.body);
      final region = data['GeolocatedCountry']?.toUpperCase() ?? '';
      if (data['isAllowed'] == true) {
        final unlockType =
            (region.isNotEmpty && region != ipCountryCode) ? "DNS" : "原生";
        return MediaUnlockInfo(
            name: 'DAZN', status: '解锁', region: region, unlockType: unlockType);
      }
      return MediaUnlockInfo(name: 'DAZN', status: '屏蔽');
    } catch (e) {
      print('❌ [DAZN] 获取失败: $e');
      return null;
    }
  }

  Future<MediaUnlockInfo> _fetchNetflixStatus(
      String ip, String ipCountryCode) async {
    try {
      final url = Uri.parse('https://www.netflix.com/title/80018499');
      final response = await _httpClient.get(url, headers: {'User-Agent': _ua});
      if (response.body.contains("Netflix Site Error"))
        return MediaUnlockInfo(name: 'Netflix', status: '检测失败');
      final regionMatch =
          RegExp(r'"countryCode"\s*:\s*"([A-Z]{2})"').firstMatch(response.body);
      final region = regionMatch?.group(1) ?? '';
      final unlockType = (region.isNotEmpty &&
              region.toUpperCase() != ipCountryCode.toUpperCase())
          ? "DNS"
          : "原生";
      final isOriginalsOnly = response.body.contains('NSEZ-403');
      if (isOriginalsOnly)
        return MediaUnlockInfo(
            name: 'Netflix',
            status: '仅自制',
            region: region,
            unlockType: unlockType);
      if (region.isNotEmpty)
        return MediaUnlockInfo(
            name: 'Netflix',
            status: '解锁',
            region: region,
            unlockType: unlockType);
      return MediaUnlockInfo(name: 'Netflix', status: '屏蔽');
    } catch (e) {
      print('❌ [Netflix] 获取失败: $e');
      return MediaUnlockInfo(name: 'Netflix', status: '检测失败');
    }
  }

  Future<MediaUnlockInfo> _fetchYoutubeStatus(String ipCountryCode) async {
    try {
      final url = Uri.parse('https://www.youtube.com/premium');
      final response = await _httpClient
          .get(url, headers: {'Accept-Language': 'en-US', 'User-Agent': _ua});
      if (response.body.contains('Premium is not available in your country')) {
        return MediaUnlockInfo(name: 'YouTube Premium', status: '不支持');
      }
      final regionMatch =
          RegExp(r'"countryCode"\s*:\s*"([A-Z]{2})"').firstMatch(response.body);
      final region = regionMatch?.group(1) ?? '';
      final unlockType = (region.isNotEmpty &&
              region.toUpperCase() != ipCountryCode.toUpperCase())
          ? "DNS"
          : "原生";
      return MediaUnlockInfo(
          name: 'YouTube Premium',
          status: '解锁',
          region: region,
          unlockType: unlockType);
    } catch (e) {
      print('❌ [YouTube] 获取失败: $e');
      return MediaUnlockInfo(name: 'YouTube Premium', status: '检测失败');
    }
  }

  Future<MediaUnlockInfo> _fetchDisneyPlusStatus() async {
    try {
      final url = Uri.parse('https://www.disneyplus.com/');
      final response = await _httpClient.get(url, headers: {'User-Agent': _ua});
      final isUnlocked =
          !response.request!.url.toString().contains('unavailable');
      return MediaUnlockInfo(name: 'Disney+', status: isUnlocked ? '解锁' : '屏蔽');
    } catch (e) {
      print('❌ [Disney+] 获取失败: $e');
      return MediaUnlockInfo(name: 'Disney+', status: '检测失败');
    }
  }

  Future<MediaUnlockInfo> _fetchChatGPTStatus(
      String ip, String ipCountryCode) async {
    try {
      final url = Uri.parse('https://chat.openai.com/cdn-cgi/trace');
      final response = await _httpClient.get(url, headers: {'User-Agent': _ua});
      if (response.statusCode != 200)
        return MediaUnlockInfo(name: 'ChatGPT', status: '屏蔽');
      final isBlocked = response.body.contains('unsupported_country');
      final locMatch = RegExp(r'loc=([A-Z]{2})').firstMatch(response.body);
      final region = locMatch?.group(1) ?? '';
      final unlockType = (region.isNotEmpty &&
              region.toUpperCase() != ipCountryCode.toUpperCase())
          ? "DNS"
          : "原生";
      return MediaUnlockInfo(
          name: 'ChatGPT',
          status: isBlocked ? '屏蔽' : '解锁',
          region: region,
          unlockType: isBlocked ? null : unlockType);
    } catch (e) {
      print('❌ [ChatGPT] 获取失败: $e');
      return MediaUnlockInfo(name: 'ChatGPT', status: '检测失败');
    }
  }

  Future<MediaUnlockInfo> _fetchTikTokStatus(String ipCountryCode) async {
    try {
      final response = await _httpClient.get(
          Uri.parse('https://www.tiktok.com/'),
          headers: {'User-Agent': _ua});
      final match =
          RegExp(r'"region"\s*:\s*"([A-Z]{2})"').firstMatch(response.body);
      if (match != null) {
        final region = match.group(1)!;
        final unlockType = (region.isNotEmpty &&
                region.toUpperCase() != ipCountryCode.toUpperCase())
            ? "DNS"
            : "原生";
        return MediaUnlockInfo(
            name: 'TikTok',
            status: '解锁',
            region: region,
            unlockType: unlockType);
      }
      return MediaUnlockInfo(name: 'TikTok', status: '屏蔽');
    } catch (e) {
      print('❌ [TikTok] 获取失败: $e');
      return MediaUnlockInfo(name: 'TikTok', status: '检测失败');
    }
  }

  Future<MediaUnlockInfo> _fetchAmazonPrimeStatus(String ipCountryCode) async {
    try {
      final response = await _httpClient.get(
          Uri.parse('https://www.primevideo.com/'),
          headers: {'User-Agent': _ua});
      final match = RegExp(r'"currentTerritory"\s*:\s*"([A-Z]{2})"')
          .firstMatch(response.body);
      if (match != null) {
        final region = match.group(1)!;
        final unlockType = (region.isNotEmpty &&
                region.toUpperCase() != ipCountryCode.toUpperCase())
            ? "DNS"
            : "原生";
        return MediaUnlockInfo(
            name: 'Amazon Prime',
            status: '解锁',
            region: region,
            unlockType: unlockType);
      }
      return MediaUnlockInfo(name: 'Amazon Prime', status: '屏蔽');
    } catch (e) {
      print('❌ [Amazon Prime] 获取失败: $e');
      return MediaUnlockInfo(name: 'Amazon Prime', status: '检测失败');
    }
  }

  Future<MediaUnlockInfo> _fetchSpotifyStatus(String ipCountryCode) async {
    try {
      final response = await _httpClient
          .get(Uri.parse('https://www.spotify.com/us/'), headers: {
        'User-Agent': _ua,
        'Accept-Language': 'en-US,en;q=0.9',
      });
      final region = response.headers['sp-country-code'] ?? '';
      if (region.isNotEmpty) {
        final unlockType = (region.isNotEmpty &&
                region.toUpperCase() != ipCountryCode.toUpperCase())
            ? "DNS"
            : "原生";
        return MediaUnlockInfo(
            name: 'Spotify',
            status: '解锁',
            region: region,
            unlockType: unlockType);
      }
      return MediaUnlockInfo(name: 'Spotify', status: '屏蔽');
    } catch (e) {
      print('❌ [Spotify] 获取失败: $e');
      return MediaUnlockInfo(name: 'Spotify', status: '检测失败');
    }
  }

  String _getRiskLevel(int? score, List<int> thresholds) {
    if (score == null) return 'N/A';
    if (score >= thresholds[1]) return '高风险';
    if (score >= thresholds[0]) return '中风险';
    return '低风险';
  }

  String _getIpqsRiskLevel(int? score) {
    if (score == null) return 'N/A';
    if (score >= 90) return '极高风险';
    if (score >= 85) return '高风险';
    if (score >= 75) return '中风险';
    return '低风险';
  }

  String _mapIpApiRiskLevel(String? levelText) {
    if (levelText == null) return '低';
    if (levelText.contains("Very High")) return '极高风险';
    if (levelText.contains("High")) return '高风险';
    if (levelText.contains("Elevated")) return '中风险';
    return '低风险';
  }

  String _generateDms(double lat, double lon) {
    String toDms(double coord, String pos, String neg) {
      final dir = coord >= 0 ? pos : neg;
      coord = coord.abs();
      final deg = coord.floor();
      final min = ((coord - deg) * 60).floor();
      final sec = (((coord - deg) * 60 - min) * 60).round();
      return '$deg°$min′$sec″$dir';
    }

    return '${toDms(lon, 'E', 'W')}, ${toDms(lat, 'N', 'S')}';
  }
}
