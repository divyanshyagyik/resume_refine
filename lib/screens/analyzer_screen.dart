import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/resume_analyzer.dart';

class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({super.key});

  @override
  State<AnalyzerScreen> createState() => _AnalyzerScreenState();
}

class _AnalyzerScreenState extends State<AnalyzerScreen> {
  File? _resumePdf;
  File? _jobDescPdf;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;
  String? _errorMessage;

  Future<void> _pickFile(bool isResume) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          if (isResume) {
            _resumePdf = File(result.files.single.path!);
          } else {
            _jobDescPdf = File(result.files.single.path!);
          }
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick file: ${e.toString()}';
      });
    }
  }

  Future<void> _analyze() async {
    if (_resumePdf == null || _jobDescPdf == null) {
      setState(() => _errorMessage = 'Please select both files');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _errorMessage = null;
    });

    try {
      final result = await ResumeAnalyzer.analyzeResume(
        resumePdf: _resumePdf!,
        jobDescPdf: _jobDescPdf!,
      );

      setState(() => _analysisResult = result);
    } catch (e) {
      setState(() {
        if (e.toString().contains('FormatException')) {
          _errorMessage = '''
Invalid response format. Please try again.
If this persists, check your prompt for JSON requirements.''';
        } else {
          _errorMessage = 'Analysis error: ${e.toString().split(':').last.trim()}';
        }
      });
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ATS Resume Analyzer'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFileSection(
              title: 'Resume PDF',
              file: _resumePdf,
              onPressed: () => _pickFile(true),
            ),
            const SizedBox(height: 20),
            _buildFileSection(
              title: 'Job Description PDF',
              file: _jobDescPdf,
              onPressed: () => _pickFile(false),
            ),
            const SizedBox(height: 30),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            ElevatedButton(
              onPressed: _isAnalyzing ? null : _analyze,
              child: _isAnalyzing
                  ? const CircularProgressIndicator()
                  : const Text('Analyze Resume'),
            ),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red),
                    ),
                    if (_errorMessage!.contains('overload')) // Show retry button
                      ElevatedButton(
                        onPressed: _analyze,
                        child: const Text('Retry Now'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 30),

            if (_analysisResult != null) _buildAnalysisResults(),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSection({
    required String title,
    required File? file,
    required VoidCallback onPressed,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    file?.path.split('/').last ?? 'No file selected',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.upload_file),
                  onPressed: onPressed,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResults() {
    final score = _analysisResult?['score']?.toDouble() ?? 0;
    final strengths = List<String>.from(_analysisResult?['strengths'] ?? []);
    final improvements = List<String>.from(_analysisResult?['improvements'] ?? []);
    final summary = _analysisResult?['summary'] ?? 'No summary provided';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analysis Results',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 30),

            Row(
              children: [
                const Text(
                  'ATS Score: ',
                  style: TextStyle(fontSize: 18),
                ),
                Text(
                  '${score.toStringAsFixed(1)}/100',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _getScoreColor(score),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Text(
              'Summary:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(summary),
            const SizedBox(height: 20),

            if (strengths.isNotEmpty) ...[
              const Text(
                'Strengths:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...strengths.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $s'),
              )),
              const SizedBox(height: 20),
            ],

            if (improvements.isNotEmpty) ...[
              const Text(
                'Suggested Improvements:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...improvements.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $i'),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orangeAccent;
    return Colors.red;
  }
}