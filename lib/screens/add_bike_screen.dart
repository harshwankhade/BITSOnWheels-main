// lib/screens/add_bike_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/bike_service.dart';
import '../widgets/multi_image_picker.dart';

class AddBikeScreen extends StatefulWidget {
  static const routeName = '/add_bike';
  const AddBikeScreen({super.key});

  @override
  State<AddBikeScreen> createState() => _AddBikeScreenState();
}

class _AddBikeScreenState extends State<AddBikeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _hourlyController = TextEditingController();

  final BikeService _bikeService = BikeService();
  List<XFile> _pickedImages = [];
  static const int maxImages = 6;
  static const double maxFileSizeMB = 5.0;

  bool _isSubmitting = false;
  double _overallProgress = 0.0; // 0..1

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _hourlyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to add a bike')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    if (_pickedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one photo')),
      );
      return;
    }

    if (_pickedImages.length > maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 6 photos allowed')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _overallProgress = 0.0;
    });

    try {
      // Upload images sequentially and compute overall progress
      final List<String> uploadedUrls = [];
      List<String> failedUploads = [];

      for (var i = 0; i < _pickedImages.length; i++) {
        final file = File(_pickedImages[i].path);
        
        // Check file size
        final bytes = await file.length();
        final sizeMB = bytes / (1024 * 1024);
        if (sizeMB > maxFileSizeMB) {
          failedUploads.add('Image ${i + 1} (${sizeMB.toStringAsFixed(1)}MB)');
          continue;
        }

        // per-image progress callback
        await _bikeService.uploadImageFile(
          file: file,
          onProgress: (p) {
            // compute aggregate progress: (completed images + current image progress) / total
            final completed = i / _pickedImages.length;
            final currentPortion = (p / _pickedImages.length);
            setState(() {
              _overallProgress = (completed + currentPortion).clamp(0.0, 1.0);
            });
          },
        ).then((url) {
          uploadedUrls.add(url);
        });
      }

      if (failedUploads.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Some images were too large (max ${maxFileSizeMB}MB): ${failedUploads.join(", ")}'),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      if (uploadedUrls.isEmpty) {
        throw Exception('No images were uploaded successfully');
      }

      // Create bike document
      final hourly = double.parse(_hourlyController.text.trim());
      await _bikeService.createBike(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        locationText: _locationController.text.trim(),
        hourlyRate: hourly,
        imageUrls: uploadedUrls,
      );

      setState(() {
        _isSubmitting = false;
        _overallProgress = 1.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bike added successfully')),
      );
      // Optionally clear form
      _formKey.currentState!.reset();
      setState(() {
        _pickedImages = [];
      });
    } catch (e, st) {
      setState(() {
        _isSubmitting = false;
        _overallProgress = 0.0;
      });
      debugPrint('Add bike error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add bike: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Bike'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Title
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title (e.g., "Road Bike - Hero Sprint")',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().length < 3) ? 'Enter a valid title' : null,
                    ),
                    const SizedBox(height: 12),

                    // Description
                    TextFormField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      validator: (v) => (v == null || v.trim().length < 8) ? 'Add a short description' : null,
                    ),
                    const SizedBox(height: 12),

                    // Location (manual)
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location (building / room / campus area)',
                        hintText: 'e.g., Block B, Rack 3 near Mess 2',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the location' : null,
                    ),
                    const SizedBox(height: 12),

                    // Hourly rate
                    TextFormField(
                      controller: _hourlyController,
                      decoration: const InputDecoration(
                        labelText: 'Hourly Rate (INR)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter hourly rate';
                        final n = double.tryParse(v.trim());
                        if (n == null || n <= 0) return 'Enter a valid rate';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Image picker
                    MultiImagePicker(
                      initialImages: _pickedImages,
                      onChanged: (imgs) {
                        setState(() {
                          _pickedImages = imgs;
                        });
                      },
                    ),

                    const SizedBox(height: 20),

                    if (_isSubmitting)
                      Column(
                        children: [
                          LinearProgressIndicator(value: _overallProgress),
                          const SizedBox(height: 8),
                          Text('${(_overallProgress * 100).toStringAsFixed(0)}% uploaded'),
                        ],
                      ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: Text(_isSubmitting ? 'Uploading...' : 'Add Bike'),
                      ),
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
}
