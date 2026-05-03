import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final apiKey = 'AIzaSyBbZVI_sO637CROKwc3hjMOB4ZmsL12ikw';
  final input = 'colombo';
  final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$apiKey';
  
  print('Requesting: $url');
  final response = await http.get(Uri.parse(url));
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
