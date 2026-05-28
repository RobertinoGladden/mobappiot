import 'dart:io';

import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:my_app/Services/ProfileService/riwayat_data_service.dart';

enum SensorExportFormat {
	csv,
	xlsx,
}

enum SensorExportFolder {
	documents,
	downloads,
}

class SensorExportResult {
	const SensorExportResult({
		required this.success,
		required this.message,
		this.filePath,
		this.fileName,
	});

	final bool success;
	final String message;
	final String? filePath;
	final String? fileName;
}

class SensorExportService {
	static Future<SensorExportResult> exportFromEndpoint({
		required SensorExportFormat format,
		int hours = 24,
		String? overrideBaseUrl,
		http.Client? client,
		bool shareAfterSave = true,
		bool openAfterSave = true,
		SensorExportFolder preferredFolder = SensorExportFolder.downloads,
	}) async {
		try {
			final rawRows = await RiwayatDataService.getSensorData(
				client: client,
				overrideBaseUrl: overrideBaseUrl,
				hours: hours,
			);

			final rows = normalizeRows(rawRows);
			if (rows.isEmpty) {
				return const SensorExportResult(
					success: false,
					message: 'Data sensor kosong. Tidak ada file yang bisa diexport.',
				);
			}

			final exportedFile = await _writeExportFile(
				rows: rows,
				format: format,
				preferredFolder: preferredFolder,
			);

			if (shareAfterSave) {
				final exportedFileName = exportedFile.path.split(Platform.pathSeparator).last;
				await Share.shareXFiles(
					[XFile(exportedFile.path)],
					text: 'File export sensor berhasil dibuat: $exportedFileName',
				);
			}

			if (openAfterSave) {
				await OpenFilex.open(exportedFile.path);
			}

			return SensorExportResult(
				success: true,
				message: 'File export berhasil disimpan.',
				filePath: exportedFile.path,
				fileName: exportedFile.path.split(Platform.pathSeparator).last,
			);
		} catch (error) {
			return SensorExportResult(
				success: false,
				message: 'Export gagal: $error',
			);
		}
	}

	static List<Map<String, dynamic>> normalizeRows(List<dynamic> rawRows) {
		final normalized = <Map<String, dynamic>>[];

		for (final item in rawRows) {
			final map = _asStringKeyedMap(item);
			if (map == null) continue;

			final flattened = <String, dynamic>{};
			_flattenMap(map, flattened);
			normalized.add(flattened);
		}

		return normalized;
	}

	static Future<File> _writeExportFile({
		required List<Map<String, dynamic>> rows,
		required SensorExportFormat format,
		required SensorExportFolder preferredFolder,
	}) async {
		final directory = await _resolveExportDirectory(preferredFolder);
		final fileName = _buildFileName(format);
		final file = File('${directory.path}${Platform.pathSeparator}$fileName');

		switch (format) {
			case SensorExportFormat.csv:
				final csvText = _buildCsv(rows);
				await file.writeAsString(csvText, flush: true);
				break;
			case SensorExportFormat.xlsx:
				final bytes = _buildXlsxBytes(rows);
				await file.writeAsBytes(bytes, flush: true);
				break;
		}

		return file;
	}

	static Future<Directory> _resolveExportDirectory(
		SensorExportFolder preferredFolder,
	) async {
		if (Platform.isAndroid) {
			await _requestAndroidStoragePermission();

			final targets = preferredFolder == SensorExportFolder.downloads
					? await getExternalStorageDirectories(type: StorageDirectory.downloads)
					: await getExternalStorageDirectories(type: StorageDirectory.documents);

			if (targets != null && targets.isNotEmpty) {
				return targets.first;
			}
		}

		return getApplicationDocumentsDirectory();
	}

	static Future<void> _requestAndroidStoragePermission() async {
		if (!Platform.isAndroid) return;

		final status = await Permission.storage.status;
		if (status.isGranted) return;

		await Permission.storage.request();
	}

	static String _buildFileName(SensorExportFormat format) {
		final now = DateTime.now();
		final yyyy = now.year.toString().padLeft(4, '0');
		final mm = now.month.toString().padLeft(2, '0');
		final dd = now.day.toString().padLeft(2, '0');
		final extension = format == SensorExportFormat.csv ? 'csv' : 'xlsx';
		return 'sensor_data_$yyyy-$mm-$dd.$extension';
	}

	static String _buildCsv(List<Map<String, dynamic>> rows) {
		final headers = _collectHeaders(rows);
		final data = <List<dynamic>>[headers];

		for (final row in rows) {
			data.add(headers.map((header) => _formatCellValue(row[header])).toList());
		}

		return const ListToCsvConverter().convert(data);
	}

	static List<int> _buildXlsxBytes(List<Map<String, dynamic>> rows) {
		final excel = Excel.createExcel();
		final defaultSheetName = excel.sheets.keys.first;
		final sheet = excel[defaultSheetName];

		final headers = _collectHeaders(rows);

		for (var i = 0; i < headers.length; i++) {
			final cell = sheet.cell(CellIndex.indexByColumnRow(
				columnIndex: i,
				rowIndex: 0,
			));
			cell.value = TextCellValue(headers[i]);
		}

		for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
			final row = rows[rowIndex];
			for (var colIndex = 0; colIndex < headers.length; colIndex++) {
				final value = _formatCellValue(row[headers[colIndex]]);
				final cell = sheet.cell(CellIndex.indexByColumnRow(
					columnIndex: colIndex,
					rowIndex: rowIndex + 1,
				));
				cell.value = TextCellValue(value);
			}
		}

		final bytes = excel.encode();
		if (bytes == null) {
			throw StateError('Gagal membuat file XLSX.');
		}

		return bytes;
	}

	static List<String> _collectHeaders(List<Map<String, dynamic>> rows) {
		final headers = <String>[];
		final seen = <String>{};

		for (final row in rows) {
			for (final key in row.keys) {
				if (seen.add(key)) {
					headers.add(key);
				}
			}
		}

		return headers;
	}

	static String _formatCellValue(dynamic value) {
		if (value == null) return '';

		if (value is DateTime) {
			return _formatTimestamp(value);
		}

		if (value is Map || value is List) {
			return value.toString();
		}

		final text = value.toString().trim();
		if (text.isEmpty) return '';

		final parsedDate = DateTime.tryParse(text);
		if (parsedDate != null) {
			return _formatTimestamp(parsedDate);
		}

		return text;
	}

	static String _formatTimestamp(DateTime dateTime) {
		const monthNames = [
			'Jan',
			'Feb',
			'Mar',
			'Apr',
			'Mei',
			'Jun',
			'Jul',
			'Agu',
			'Sep',
			'Okt',
			'Nov',
			'Des',
		];

		final local = dateTime.toLocal();
		final day = local.day.toString().padLeft(2, '0');
		final month = monthNames[local.month - 1];
		final year = local.year;
		final hour = local.hour.toString().padLeft(2, '0');
		final minute = local.minute.toString().padLeft(2, '0');
		return '$day $month $year $hour:$minute';
	}

	static Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
		if (value is! Map) return null;

		return value.map(
			(key, dynamic nestedValue) => MapEntry(key.toString(), nestedValue),
		);
	}

	static void _flattenMap(
		Map<String, dynamic> source,
		Map<String, dynamic> target, [
		String prefix = '',
	]) {
		for (final entry in source.entries) {
			final key = prefix.isEmpty ? entry.key : '${prefix}_${entry.key}';
			final value = entry.value;

			if (value is Map) {
				_flattenMap(_asStringKeyedMap(value) ?? <String, dynamic>{}, target, key);
			} else if (value is List) {
				target[key] = value.map(_formatCellValue).join(', ');
			} else {
				target[key] = _formatCellValue(value);
			}
		}
	}
}
