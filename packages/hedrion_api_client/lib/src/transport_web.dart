import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

const browserTransport = true;
http.Client createTransport() => BrowserClient()..withCredentials = true;
