// 文件 2/3: lib/services/report_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_curl/flutter_curl.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import '../models/ip_report.dart';

class ReportService {
  final Client _curlClient = Client(verbose: true);
  final http.Client _httpClient = http.Client();
  final String _browserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  Future<T?> _guardedFetch<T>(String apiName, Future<T> Function() fetcher) async {
    try {
      return await fetcher();
    } catch (e) {
      print('❌ Failed to fetch from [$apiName]: $e');
      return null;
    }
  }

  Future<dynamic> _curlGetAndParse(String url) async {
    final request = Request(method: 'GET', url: url, headers: {'User-Agent': 'curl/8.5.0'});
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
    final initialRequest = Request(method: 'GET', url: initialUrl, headers: {'User-Agent': 'curl/8.5.0'});
    final initialResponse = await _curlClient.send(initialRequest);

    if (initialResponse.statusCode == 302) {
      final location = initialResponse.headers['location'];
      if (location == null || location.isEmpty) throw Exception('302 Redirect: No location header.');
      print('✅ IPQS Redirect: Following to: $location');
      final finalRequest = Request(method: 'GET', url: location, headers: {'User-Agent': 'curl/8.5.0'});
      final finalResponse = await _curlClient.send(finalRequest);
      if (finalResponse.statusCode == 200) {
        if (finalResponse.body.isEmpty) throw Exception('Final response body is empty.');
        return jsonDecode(finalResponse.text());
      } else {
        throw Exception('Redirected request failed: Status Code ${finalResponse.statusCode}');
      }
    } else if (initialResponse.statusCode == 200) {
      if (initialResponse.body.isEmpty) throw Exception('Initial response body is empty.');
      return jsonDecode(initialResponse.text());
    } else {
      throw Exception('Initial request failed: Status Code ${initialResponse.statusCode}');
    }
  }

  Stream<ReportUpdate> streamReport() async* {
    await _curlClient.init();

    final ipResponse = await _httpClient.get(Uri.parse('https://api.ipify.org?format=json'));
    if (ipResponse.statusCode != 200) throw Exception('Failed to get public IP');
    final String ip = jsonDecode(ipResponse.body)['ip'];
    
    final basicInfoFuture = Future.wait([
      _guardedFetch('Maxmind', () => _fetchMaxmindData(ip)),
      _guardedFetch('IPinfo', () => _fetchIpInfoData(ip)),
    ]);
    
    // 启动所有其他请求
    final otherDataFuture = Future.wait([
      _guardedFetch('Scamalytics', () => _fetchScamalyticsData(ip)),
      _guardedFetch('IPQS', () => _fetchIpqsDataWithRedirect(ip)),
      _guardedFetch('ip-api.is', () => _fetchIpApiData(ip)),
      _guardedFetch('AbuseIPDB', () => _curlGetAndParse('https://ipinfo.check.place/$ip?db=abuseipdb')),
      _guardedFetch('IP2Location', () => _curlGetAndParse('https://ipinfo.check.place/$ip?db=ip2location')),
      _guardedFetch('ipregistry', () => _curlGetAndParse('https://ipinfo.check.place/$ip?db=ipregistry')),
      _guardedFetch('DB-IP', () => _fetchDbIpData(ip)),
      _guardedFetch('Cloudflare', () => _fetchCloudflareData(ip)),
      _guardedFetch('ipdata', () => _curlGetAndParse('https://ipinfo.check.place/$ip?db=ipdata')),
      _guardedFetch('IPWHOIS', () => _fetchIpWhoisData(ip)),
    ]);
    final mediaFutures = [
      _guardedFetch('Netflix', () => _fetchNetflixStatus()),
      _guardedFetch('YouTube', () => _fetchYoutubeStatus()),
      _guardedFetch('Disney+', () => _fetchDisneyPlusStatus()),
      _guardedFetch('ChatGPT', () => _fetchChatGPTStatus()),
    ];

    final basicInfoResults = await basicInfoFuture;
    final maxmindData = basicInfoResults[0];
    final ipInfoData = basicInfoResults[1];

    late BasicInfo basicInfo;
    // ... 基础信息回退逻辑 ...
    yield BasicInfoUpdate(basicInfo);

    // 流媒体优先加载
    final mediaStream = Stream.fromFutures(mediaFutures);
    final List<MediaUnlockInfo> mediaInfos = [];
    await for (final mediaInfo in mediaStream) {
      if (mediaInfo != null) {
        mediaInfos.add(mediaInfo);
        yield MediaUnlockUpdate(List.from(mediaInfos));
      }
    }

    // 等待所有风险数据完成
    final otherResults = await otherDataFuture;
    // ... 解析所有风险数据 ...

    // 流出IP类型
    final ipTypes = { /* ... */ };
    yield IpTypesUpdate(ipTypes);

    // 流出风险评分
    final riskScores = { /* ... */ };
    yield RiskScoresUpdate(riskScores);

    // 流出风险因子
    final riskFactors = RiskFactors(/* ... */);
    yield RiskFactorsUpdate(riskFactors);
  }
  
  // --- 所有 _fetch...Data 和辅助函数 ---

  Future<Map<String, dynamic>> _fetchMaxmindData(String ip) async {/* ... */}
  Future<Map<String, dynamic>> _fetchIpInfoData(String ip) async { /* ... */}
  Future<Map<String, dynamic>> _fetchScamalyticsData(String ip) async { /* ... */}
  Future<Map<String, dynamic>> _fetchIpApiData(String ip) async { /* ... */}
  Future<Map<String, dynamic>> _fetchDbIpData(String ip) async { /* ... */}
  Future<Map<String, dynamic>> _fetchCloudflareData(String ip) async { /* ... */}
  Future<Map<String, dynamic>> _fetchIpWhoisData(String ip) async { /* ... */}
  String _getRiskLevel(int? score, List<int> thresholds) { /* ... */}
  String _getIpqsRiskLevel(int? score) { /* ... */}
  String _mapIpApiRiskLevel(String? levelText) { /* ... */}
  String _generateDms(double lat, double lon) { /* ... */}
  
  // --- 详细的流媒体检测函数 ---

  Future<MediaUnlockInfo> _fetchNetflixStatus() async {
    try {
      final title1Future = _httpClient.get(Uri.parse('https://www.netflix.com/title/81280792'), headers: {'User-Agent': _browserUserAgent});
      final title2Future = _httpClient.get(Uri.parse('https://www.netflix.com/title/70143836'), headers: {'User-Agent': _browserUserAgent});
      final responses = await Future.wait([title1Future, title2Future]);

      final res1 = responses[0];
      final res2 = responses[1];
      
      final regionMatch = RegExp(r'"countryCode"\s*:\s*"([A-Z]{2})"').firstMatch(res1.body);
      final region = regionMatch?.group(1) ?? '';

      final isBlocked1 = res1.statusCode != 200 || res1.body.contains('Oh no!');
      final isBlocked2 = res2.statusCode != 200;

      if (!isBlocked1 && !isBlocked2) {
        return MediaUnlockInfo(name: 'Netflix', status: '解锁', region: region);
      } else if (!isBlocked2) {
        return MediaUnlockInfo(name: 'Netflix', status: '仅自制', region: region);
      } else {
        return MediaUnlockInfo(name: 'Netflix', status: '屏蔽', region: region);
      }
    } catch (e) {
      return MediaUnlockInfo(name: 'Netflix', status: '失败');
    }
  }

  Future<MediaUnlockInfo> _fetchYoutubeStatus() async {
    try {
      final url = Uri.parse('https://www.youtube.com/premium');
      final response = await _httpClient.get(url, headers: {'Accept-Language': 'en', 'User-Agent': _browserUserAgent});
      
      if (response.statusCode != 200) {
        return MediaUnlockInfo(name: 'YouTube', status: '屏蔽');
      }
      final isNotAvailable = response.body.contains('Premium is not available in your country');
      if (isNotAvailable) {
        return MediaUnlockInfo(name: 'YouTube', status: '禁会员区');
      }
      final regionMatch = RegExp(r'"countryCode"\s*:\s*"([A-Z]{2})"').firstMatch(response.body);
      return MediaUnlockInfo(name: 'YouTube', status: '解锁', region: regionMatch?.group(1) ?? '');
    } catch (e) {
      return MediaUnlockInfo(name: 'YouTube', status: '失败');
    }
  }

  Future<MediaUnlockInfo> _fetchDisneyPlusStatus() async {
    try {
      final url = Uri.parse('https://www.disneyplus.com/');
      final response = await _httpClient.get(url, headers: {'User-Agent': _browserUserAgent});
      if (response.request!.url.toString().contains('unavailable')) {
        return MediaUnlockInfo(name: 'Disney+', status: '屏蔽');
      }
      return MediaUnlockInfo(name: 'Disney+', status: '解锁');
    } catch (e) {
      return MediaUnlockInfo(name: 'Disney+', status: '失败');
    }
  }
  
  Future<MediaUnlockInfo> _fetchChatGPTStatus() async {
    try {
      final apiFuture = _httpClient.get(Uri.parse('https://chat.openai.com/backend-api/models'), headers: {'User-Agent': _browserUserAgent});
      final webFuture = _httpClient.get(Uri.parse('https://chat.openai.com/'), headers: {'User-Agent': _browserUserAgent});
      final responses = await Future.wait([apiFuture, webFuture]);
      
      final apiAllowed = responses[0].statusCode == 200;
      final webAllowed = responses[1].statusCode == 200;
      final countryMatch = RegExp(r'loc=([A-Z]{2})').firstMatch(await _httpClient.get(Uri.parse('https://chat.openai.com/cdn-cgi/trace')).then((res) => res.body));
      final region = countryMatch?.group(1) ?? '';

      if (apiAllowed && webAllowed) {
        return MediaUnlockInfo(name: 'ChatGPT', status: '解锁', region: region);
      } else if (apiAllowed) {
        return MediaUnlockInfo(name: 'ChatGPT', status: '仅API', region: region);
      } else if (webAllowed) {
        return MediaUnlockInfo(name: 'ChatGPT', status: '仅网页', region: region);
      } else {
        return MediaUnlockInfo(name: 'ChatGPT', status: '屏蔽', region: region);
      }
    } catch (e) {
      return MediaUnlockInfo(name: 'ChatGPT', status: '失败');
    }
  }
}