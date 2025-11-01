// lib/screens/add_bike_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/bike_service.dart';
import '../widgets/multi_image_picker.dart';
import '../models/bike.dart';

class AddBikeScreen extends StatefulWidget {
  static const routeName = '/add_bike';

  /// If [bike] is provided, the screen will act as an "Edit Bike" form.
  final Bike? bike;
  const AddBikeScreen({super.key, this.bike});

  @override
  State<AddBikeScreen> createState() => _AddBikeScreenState();
}

class _AddBikeScreenState extends State<AddBikeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _hourlyController = TextEditingController();
  final _contactController = TextEditingController();

  final BikeService _bikeService = BikeService();

  // Newly picked files (not yet uploaded)
  List<XFile> _pickedImages = [];

  // Existing image URLs already stored in Firestore (used in edit flow).
  List<String> _existingImageUrls = [];

  // Keep a copy of original existing images to compute removedImageUrls on update
  List<String> _originalExistingImageUrls = [];

  static const int maxImages = 6;
  static const double maxFileSizeMB = 5.0;

  static const List<String> locationOptions = [
    'SR Bhawan',
    'Malviya Bhawan',
    'Budh Bhawan',
    'Ram Bhawan',
    'Vyas Bhawan',
    'Krishna Bhawan',
    'Meera Bhawan',
  ];

  bool _isSubmitting = false;
  double _overallProgress = 0.0; // 0..1

  bool get isEditing => widget.bike != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final b = widget.bike!;
      _titleController.text = b.title;
      _descController.text = b.description;
      _locationController.text = b.locationText;
      _hourlyController.text = b.hourlyRate.toStringAsFixed(0);
      _contactController.text = b.contactNumber;
      _existingImageUrls = List<String>.from(b.images);
      _originalExistingImageUrls = List<String>.from(b.images);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _hourlyController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  /// Validates and submits the form.
  /// For create: uploads picked images, calls createBike(...)
  /// For edit: uploads newly picked images, computes removedImageUrls and calls updateBike(...)
  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to add or edit a bike')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // Combined count (existing kept + newly picked) must be > 0 and <= maxImages
    final totalImageCount = _existingImageUrls.length + _pickedImages.length;
    if (totalImageCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one photo')),
      );
      return;
    }
    if (totalImageCount > maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $maxImages photos allowed')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _overallProgress = 0.0;
    });

    try {
      // Upload newly picked images (if any) and collect their URLs
      final List<String> uploadedUrls = [];
      final List<String> failedUploads = [];

      for (var i = 0; i < _pickedImages.length; i++) {
        final file = File(_pickedImages[i].path);
        final bytes = await file.length();
        final sizeMB = bytes / (1024 * 1024);
        if (sizeMB > maxFileSizeMB) {
          failedUploads.add('Image ${i + 1} (${sizeMB.toStringAsFixed(1)}MB)');
          continue;
        }

        final url = await _bikeService.uploadImageFile(
          file: file,
          onProgress: (p) {
            // measure overall progress: portion for new images only
            final baseOffset = 0.0; // we only show progress for new uploads here
            // progress partitioned by number of new images
            final completed = i / (_pickedImages.length == 0 ? 1 : _pickedImages.length);
            final currentPortion = (p / (_pickedImages.length == 0 ? 1 : _pickedImages.length));
            setState(() {
              _overallProgress = (baseOffset + completed + currentPortion).clamp(0.0, 1.0);
            });
          },
        );

        if (url.isNotEmpty) uploadedUrls.add(url);
      }

      if (failedUploads.isNotEmpty) {
        setState(() {
          _isSubmitting = false;
          _overallProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Some images were too large (max ${maxFileSizeMB}MB): ${failedUploads.join(", ")}'),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      // Build final image list: existing kept ones + newly uploaded
      final finalImageUrls = [..._existingImageUrls, ...uploadedUrls];

      // Common fields
      final hourly = double.parse(_hourlyController.text.trim());
      final title = _titleController.text.trim();
      final description = _descController.text.trim();
      final locationText = _locationController.text.trim();
      final contactNumber = _contactController.text.trim();

      String resultBikeId;

      if (isEditing) {
        // Editing: compute removed images (images removed by user from original)
        final removedImageUrls = _originalExistingImageUrls.where((u) => !_existingImageUrls.contains(u)).toList();

        await _bikeService.updateBike(
          bikeId: widget.bike!.id,
          title: title,
          description: description,
          locationText: locationText,
          hourlyRate: hourly,
          newImageUrls: finalImageUrls,
          removedImageUrls: removedImageUrls,
          contactNumber: contactNumber,
        );

        resultBikeId = widget.bike!.id;
      } else {
        // Creating new bike
        final docRef = await _bikeService.createBike(
          title: title,
          description: description,
          locationText: locationText,
          hourlyRate: hourly,
          imageUrls: finalImageUrls,
          contactNumber: contactNumber,
        );
        resultBikeId = docRef.id;
      }

      setState(() {
        _isSubmitting = false;
        _overallProgress = 1.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEditing ? 'Bike updated successfully' : 'Bike added successfully')),
      );

      // Return the created/updated bike ID so caller can refresh or navigate to details
      Navigator.pop(context, resultBikeId);
    } catch (e, st) {
      setState(() {
        _isSubmitting = false;
        _overallProgress = 0.0;
      });
      debugPrint('Add/Edit bike error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to ${isEditing ? 'update' : 'add'} bike: ${e.toString()}')),
      );
    }
  }

  /// Helper to remove an existing image URL from the kept list (UI action).
  void _removeExistingImage(String url) {
    setState(() {
      _existingImageUrls.remove(url);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Bike' : 'Add Bike'),
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

                    // Location Dropdown
                    DropdownButtonFormField<String>(
                      value: _locationController.text.isNotEmpty ? _locationController.text : null,
                      decoration: const InputDecoration(
                        labelText: 'Location (Bhawan)',
                        border: OutlineInputBorder(),
                      ),
                      items: locationOptions.map((String location) {
                        return DropdownMenuItem<String>(
                          value: location,
                          child: Text(location),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          _locationController.text = newValue;
                        }
                      },
                      validator: (v) => v == null ? 'Please select a location' : null,
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
                    const SizedBox(height: 12),

                    // Contact Number
                    TextFormField(
                      controller: _contactController,
                      decoration: const InputDecoration(
                        labelText: 'Contact Number',
                        hintText: 'Enter your 10-digit mobile number',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Enter your contact number';
                        if (v.trim().length != 10) return 'Enter a valid 10-digit number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Existing images (only for edit) - show thumbnails with remove action
                    if (_existingImageUrls.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'Existing Photos (tap X to remove)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _existingImageUrls.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final url = _existingImageUrls[index];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, st) => Container(
                                      width: 100,
                                      height: 100,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => _removeExistingImage(url),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(Icons.close, size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Image picker (for new images to be uploaded)
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
                        child: Text(_isSubmitting ? (isEditing ? 'Updating...' : 'Uploading...') : (isEditing ? 'Update Bike' : 'Add Bike')),
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
