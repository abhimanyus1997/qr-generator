import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const QrAutomateApp());
}

class QrAutomateApp extends StatelessWidget {
  const QrAutomateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Automation Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
        fontFamily: 'Poppins',
      ),
      home: const QrGeneratorPage(),
    );
  }
}

// --- Data Model ---
class QrData {
  final String id;
  final String text;
  final String url;
  QrData({required this.id, required this.text, required this.url});
}

class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({super.key});

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  // --- Data ---
  List<QrData> _qrDataList = [];
  File? _csvFile;
  File? _templateFile;
  ui.Image? _decodedTemplate;

  // --- Mode Switching ---
  bool _isPatternMode = false; // Toggle between CSV and Pattern

  // --- Pattern Controllers ---
  final TextEditingController _urlPatternCtrl = TextEditingController(
    text: "https://example.com/room-*",
  );
  final TextEditingController _textPatternCtrl = TextEditingController(
    text: "Room *",
  );
  final TextEditingController _idPatternCtrl = TextEditingController(
    text: "file-*",
  );
  final TextEditingController _startRangeCtrl = TextEditingController(
    text: "1",
  );
  final TextEditingController _endRangeCtrl = TextEditingController(text: "10");

  // --- UI State ---
  bool _isGenerating = false;
  double _progress = 0.0;
  File? _generatedZipFile;
  int? _previewIndex;

  // --- Design Settings ---
  Offset _qrPos = const Offset(0.5, 0.4);
  Offset _textPos = const Offset(0.5, 0.8);
  double _qrSizeRatio = 0.3;
  double _textSizeRatio = 0.05;

  // Style
  String _textPrefix = "Room ";
  Color _textColor = Colors.black;
  Color _textBgColor = Colors.white;
  bool _isTextBgTransparent = true;
  bool _isBold = true;
  bool _isItalic = false;

  // Font
  String _selectedFont = 'Poppins';
  File? _customFontFile;
  final List<String> _googleFonts = [
    'Poppins',
    'Roboto',
    'Open Sans',
    'Lato',
    'Montserrat',
    'Oswald',
    'Playfair Display',
  ];

  late TextEditingController _prefixController;
  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _prefixController = TextEditingController(text: _textPrefix);
    _prefixController.addListener(() {
      setState(() => _textPrefix = _prefixController.text);
    });
  }

  // ==========================================
  // 1. Logic (CSV & Pattern)
  // ==========================================

  Future<void> _pickCsv() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null) return;

    try {
      final file = File(result.files.single.path!);
      final input = file.openRead();
      final fields = await input
          .transform(utf8.decoder)
          .transform(const CsvToListConverter())
          .toList();

      if (fields.isEmpty) return _showMsg("CSV is empty", isError: true);

      final headers = fields[0]
          .map((e) => e.toString().trim().toLowerCase())
          .toList();
      final idIdx = headers.indexOf('id');
      final txtIdx = headers.indexOf('text');
      final urlIdx = headers.indexOf('url');

      if (idIdx == -1 || txtIdx == -1 || urlIdx == -1) {
        return _showMsg("CSV needs 'ID', 'Text', 'URL' headers", isError: true);
      }

      final data = <QrData>[];
      for (var i = 1; i < fields.length; i++) {
        final row = fields[i];
        if (row.length > urlIdx && row.length > txtIdx && row.length > idIdx) {
          data.add(
            QrData(
              id: row[idIdx].toString(),
              text: row[txtIdx].toString(),
              url: row[urlIdx].toString(),
            ),
          );
        }
      }
      setState(() {
        _csvFile = file;
        _qrDataList = data;
        _generatedZipFile = null;
        _isPatternMode = false; // Switch to CSV mode visual
      });
      _showMsg("Loaded ${data.length} rows from CSV");
    } catch (e) {
      _showMsg("Error reading CSV: $e", isError: true);
    }
  }

  void _generatePatternData() {
    // 1. Validate inputs
    final start = int.tryParse(_startRangeCtrl.text);
    final end = int.tryParse(_endRangeCtrl.text);
    final urlPat = _urlPatternCtrl.text;
    final textPat = _textPatternCtrl.text;
    final idPat = _idPatternCtrl.text;

    if (start == null || end == null) {
      return _showMsg("Invalid Start or End range numbers", isError: true);
    }
    if (end < start) {
      return _showMsg("End range must be greater than Start", isError: true);
    }
    if (!urlPat.contains('*') &&
        !textPat.contains('*') &&
        !idPat.contains('*')) {
      // Just a warning, maybe they want static data?
    }

    // 2. Generate
    final data = <QrData>[];
    for (int i = start; i <= end; i++) {
      data.add(
        QrData(
          id: idPat.replaceAll('*', '$i'),
          text: textPat.replaceAll('*', '$i'),
          url: urlPat.replaceAll('*', '$i'),
        ),
      );
    }

    setState(() {
      _qrDataList = data;
      _csvFile = null; // Clear CSV file visual
      _generatedZipFile = null;
    });

    _showMsg("Generated ${data.length} entries from pattern!");
    // Auto-open editor
    if (_templateFile != null) {
      setState(() => _previewIndex = 0);
    }
  }

  Future<void> _pickTemplate() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() {
        _templateFile = file;
        _decodedTemplate = frame.image;
        _generatedZipFile = null;
      });
    }
  }

  Future<void> _pickFont() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null) {
      final file = File(result.files.single.path!);
      if (file.path.endsWith('.ttf') || file.path.endsWith('.otf')) {
        await _loadCustomFont(file);
        setState(() {
          _customFontFile = file;
          _selectedFont = 'Custom';
        });
      }
    }
  }

  Future<void> _loadCustomFont(File f) async {
    try {
      final bytes = await f.readAsBytes();
      final loader = FontLoader('CustomFont');
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    } catch (e) {
      _showMsg("Font error: $e", isError: true);
    }
  }

  // ==========================================
  // 2. Generation Logic (Widget Screenshot)
  // ==========================================

  Future<void> _generateAll() async {
    if (_qrDataList.isEmpty || _decodedTemplate == null) return;
    if (Platform.isAndroid) await Permission.storage.request();

    setState(() {
      _isGenerating = true;
      _progress = 0.0;
      _generatedZipFile = null;
    });

    try {
      final archive = Archive();

      for (int i = 0; i < _qrDataList.length; i++) {
        setState(() {
          _previewIndex = i;
        });
        await Future.delayed(const Duration(milliseconds: 50));

        RenderRepaintBoundary? boundary =
            _captureKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) continue;

        double renderWidth = boundary.size.width;
        double targetWidth = _decodedTemplate!.width.toDouble();
        double pixelRatio = targetWidth / renderWidth;

        ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
        ByteData? byteData = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );

        if (byteData != null) {
          List<int> pngBytes = byteData.buffer.asUint8List();
          archive.addFile(
            ArchiveFile('${_qrDataList[i].id}.png', pngBytes.length, pngBytes),
          );
        }

        setState(() => _progress = (i + 1) / _qrDataList.length);
      }

      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      if (zipData != null) {
        final tempDir = await getTemporaryDirectory();
        final zipFile = File('${tempDir.path}/cards_batch.zip');
        await zipFile.writeAsBytes(zipData);

        setState(() {
          _generatedZipFile = zipFile;
          _previewIndex = null;
          _isGenerating = false;
        });
        _showMsg(
          "Success! ${_qrDataList.length} cards generated.",
          isError: false,
        );
      }
    } catch (e) {
      _showMsg("Error: $e", isError: true);
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _shareZip() async {
    if (_generatedZipFile != null) {
      await Share.shareXFiles([XFile(_generatedZipFile!.path)]);
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================
  // 3. UI Construction
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("QR Automation Studio"),
        actions: [
          if (_previewIndex == null && !_isGenerating)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: "About Developer",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutDeveloperDialog(),
                  ),
                );
              },
            ),
          if (_previewIndex != null && !_isGenerating)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton(
                onPressed: () => setState(() => _previewIndex = null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: const Text("Done"),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // A. DASHBOARD
          if (_previewIndex == null && !_isGenerating) _buildDashboard(),

          // B. VISUAL EDITOR
          if (_previewIndex != null && !_isGenerating)
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: _buildCardWidget(_qrDataList[_previewIndex!]),
                    ),
                  ),
                ),
                _buildControlPanel(),
              ],
            ),

          // C. HIDDEN GENERATOR
          if (_isGenerating)
            Transform.translate(
              offset: const Offset(9999, 9999),
              child: Center(
                child: _buildCardWidget(_qrDataList[_previewIndex ?? 0]),
              ),
            ),

          // D. LOADING
          if (_isGenerating)
            Container(
              color: Colors.white.withOpacity(0.95),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.blueAccent),
                    const SizedBox(height: 20),
                    Text(
                      "Generating ${(_progress * 100).toInt()}%",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Processing ${_qrDataList.length} files...",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Dashboard ---
  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF9333EA)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.qr_code_2, color: Colors.white, size: 40),
                SizedBox(height: 10),
                Text(
                  "Bulk QR Generator",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Upload CSV or use Pattern to automate card creation.",
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // MODE SWITCHER
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Data Source",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildModeToggle("CSV Upload", false),
                    _buildModeToggle("Pattern", true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // DATA INPUT AREA
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isPatternMode
                ? _buildPatternForm() // NEW PATTERN FORM
                : Row(
                    key: const ValueKey("CSV"),
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          Icons.table_chart_rounded,
                          "CSV Data",
                          _csvFile != null
                              ? "Loaded (${_qrDataList.length})"
                              : "Upload CSV",
                          Colors.orange.shade50,
                          Colors.orange,
                          _pickCsv,
                        ),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 15),

          // TEMPLATE & FONT ROW
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  Icons.image_rounded,
                  "Template",
                  _templateFile != null ? "Ready" : "Upload Image",
                  Colors.purple.shade50,
                  Colors.purple,
                  _pickTemplate,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildInfoCard(
                  Icons.text_fields_rounded,
                  "Custom Font",
                  _customFontFile != null
                      ? "Custom Active"
                      : "Default: Poppins",
                  Colors.blue.shade50,
                  Colors.blue,
                  _pickFont,
                ),
              ),
            ],
          ),

          // Actions
          if (_qrDataList.isNotEmpty && _templateFile != null) ...[
            const SizedBox(height: 30),
            const Text(
              "Actions",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.design_services),
                label: const Text("Open Visual Editor"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => setState(() => _previewIndex = 0),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.rocket_launch),
                label: const Text("Generate All Files"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _generateAll,
              ),
            ),
          ],

          // Results
          if (_generatedZipFile != null) ...[
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 40),
                  const SizedBox(height: 10),
                  const Text(
                    "Processing Complete!",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text("Share / Save ZIP"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _shareZip,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeToggle(String text, bool isPattern) {
    bool isSelected = _isPatternMode == isPattern;
    return GestureDetector(
      onTap: () => setState(() => _isPatternMode = isPattern),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.blue : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildPatternForm() {
    return Container(
      key: const ValueKey("Pattern"),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.generating_tokens,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Generate Sequence",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            "Use '*' as the wildcard number placeholder.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Divider(height: 30),

          // URL Pattern
          _buildPatternField(
            "URL Pattern (QR Content)",
            _urlPatternCtrl,
            Icons.link,
          ),
          const SizedBox(height: 10),

          // Text Pattern
          _buildPatternField(
            "Text Label Pattern",
            _textPatternCtrl,
            Icons.text_fields,
          ),
          const SizedBox(height: 10),

          // ID Pattern
          _buildPatternField(
            "Filename ID Pattern",
            _idPatternCtrl,
            Icons.folder_open,
          ),
          const SizedBox(height: 15),

          // Range
          Row(
            children: [
              Expanded(
                child: _buildPatternField(
                  "Start #",
                  _startRangeCtrl,
                  Icons.first_page,
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildPatternField(
                  "End #",
                  _endRangeCtrl,
                  Icons.last_page,
                  isNumber: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generatePatternData,
              icon: const Icon(Icons.check),
              label: const Text("Apply Pattern"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : [],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: Colors.grey),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    IconData icon,
    String title,
    String subtitle,
    Color bg,
    Color accent,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // --- Control Panel (Split View) ---
  Widget _buildControlPanel() {
    return Container(
      height: 320, // Fixed height for controls
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 40,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.blue,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [
                      Tab(text: "Layout"),
                      Tab(text: "Typography"),
                      Tab(text: "Style"),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildLayoutTab(),
                        _buildTypeTab(),
                        _buildStyleTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Navigation Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _previewIndex! > 0
                      ? () => setState(() => _previewIndex = _previewIndex! - 1)
                      : null,
                ),
                Text(
                  "Item ${_previewIndex! + 1} / ${_qrDataList.length}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _previewIndex! < _qrDataList.length - 1
                      ? () => setState(() => _previewIndex = _previewIndex! + 1)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Tabs Content ---
  Widget _buildLayoutTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Drag the QR Code and Text directly on the image to position them.",
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "QR Code Size",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Slider(
          value: _qrSizeRatio,
          min: 0.1,
          max: 0.6,
          onChanged: (v) => setState(() => _qrSizeRatio = v),
        ),
        const SizedBox(height: 20),
        const Text("Text Size", style: TextStyle(fontWeight: FontWeight.bold)),
        Slider(
          value: _textSizeRatio,
          min: 0.01,
          max: 0.15,
          onChanged: (v) => setState(() => _textSizeRatio = v),
        ),
      ],
    );
  }

  Widget _buildTypeTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _prefixController,
          decoration: InputDecoration(
            labelText: "Prefix",
            hintText: "e.g. Room ",
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text("Font Style", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            FilterChip(
              label: const Text("Bold"),
              selected: _isBold,
              onSelected: (v) => setState(() => _isBold = v),
            ),
            const SizedBox(width: 10),
            FilterChip(
              label: const Text("Italic"),
              selected: _isItalic,
              onSelected: (v) => setState(() => _isItalic = v),
            ),
          ],
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: _selectedFont,
          decoration: InputDecoration(
            labelText: "Font Family",
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            ..._googleFonts.map(
              (f) => DropdownMenuItem(value: f, child: Text(f)),
            ),
            if (_customFontFile != null)
              const DropdownMenuItem(
                value: 'Custom',
                child: Text("Custom Font"),
              ),
          ],
          onChanged: (v) => setState(() => _selectedFont = v!),
        ),
      ],
    );
  }

  Widget _buildStyleTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text("Text Color", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _colorPicker((c) => setState(() => _textColor = c), _textColor),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Background Color",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                const Text("Transparent", style: TextStyle(fontSize: 12)),
                Switch(
                  value: _isTextBgTransparent,
                  onChanged: (v) => setState(() => _isTextBgTransparent = v),
                ),
              ],
            ),
          ],
        ),
        if (!_isTextBgTransparent)
          _colorPicker((c) => setState(() => _textBgColor = c), _textBgColor),
      ],
    );
  }

  Widget _colorPicker(Function(Color) onSelect, Color current) {
    final colors = [
      Colors.black,
      Colors.white,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      const Color(0xFF1E1E1E),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: colors
            .map(
              (c) => GestureDetector(
                onTap: () => onSelect(c),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: current == c ? Colors.blue : Colors.grey.shade300,
                      width: current == c ? 3 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // --- Render Widget (The Engine) ---
  Widget _buildCardWidget(QrData data) {
    if (_decodedTemplate == null) return const SizedBox();

    return AspectRatio(
      aspectRatio: _decodedTemplate!.width / _decodedTemplate!.height,
      child: RepaintBoundary(
        key: _captureKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.file(_templateFile!, fit: BoxFit.contain),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(
                    children: [
                      _buildDraggable(
                        w,
                        h,
                        _qrPos,
                        (p) => setState(() => _qrPos = p),
                        Container(
                          width: w * _qrSizeRatio,
                          height: w * _qrSizeRatio,
                          decoration: const BoxDecoration(color: Colors.white),
                          padding: EdgeInsets.all(w * 0.015),
                          child: QrImageView(
                            data: data.url,
                            version: QrVersions.auto,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      _buildDraggable(
                        w,
                        h,
                        _textPos,
                        (p) => setState(() => _textPos = p),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _isTextBgTransparent
                                ? Colors.transparent
                                : _textBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "$_textPrefix${data.text}",
                            style: _selectedFont == 'Custom'
                                ? TextStyle(
                                    fontFamily: 'CustomFont',
                                    color: _textColor,
                                    fontSize: w * _textSizeRatio,
                                    fontWeight: _isBold
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontStyle: _isItalic
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  )
                                : GoogleFonts.getFont(
                                    _selectedFont,
                                    color: _textColor,
                                    fontSize: w * _textSizeRatio,
                                    fontWeight: _isBold
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontStyle: _isItalic
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggable(
    double parentW,
    double parentH,
    Offset relPos,
    Function(Offset) onDrag,
    Widget child,
  ) {
    bool interactable = !_isGenerating;
    return Positioned(
      left: parentW * relPos.dx,
      top: parentH * relPos.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onPanUpdate: interactable
              ? (d) {
                  final dx = d.delta.dx / parentW;
                  final dy = d.delta.dy / parentH;
                  onDrag(
                    Offset(
                      (relPos.dx + dx).clamp(0.0, 1.0),
                      (relPos.dy + dy).clamp(0.0, 1.0),
                    ),
                  );
                }
              : null,
          child: child,
        ),
      ),
    );
  }
}

// ==========================================
// About Developer Dialog
// ==========================================

class AboutDeveloperDialog extends StatelessWidget {
  const AboutDeveloperDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF9333EA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                    bottom: Radius.circular(40),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white,
                        backgroundImage: NetworkImage(
                          'https://github.com/abhimanyus1997.png',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Abhimanyu Singh",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Software Developer | AI & Mobile Enthusiast",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildLinkTile(
                      icon: Icons.link,
                      title: "LinkedIn",
                      subtitle: "linkedin.com/in/abhimanyus1997",
                      color: Colors.blue.shade50,
                      iconColor: Colors.blue,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Visit linkedin.com/in/abhimanyus1997"),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    _buildLinkTile(
                      icon: Icons.code,
                      title: "GitHub",
                      subtitle: "github.com/abhimanyus1997",
                      color: Colors.grey.shade100,
                      iconColor: Colors.black87,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Visit github.com/abhimanyus1997"),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      "Built with Flutter 💙",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
