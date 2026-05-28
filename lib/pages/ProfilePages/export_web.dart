// Implementasi untuk platform web — menggunakan dart:html
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadFileWeb(List<int> bytes, String fileName, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
