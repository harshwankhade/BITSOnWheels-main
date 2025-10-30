// lib/widgets/multi_image_picker.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MultiImagePicker extends StatefulWidget {
  final List<XFile> initialImages;
  final void Function(List<XFile>) onChanged;

  const MultiImagePicker({
    super.key,
    required this.initialImages,
    required this.onChanged,
  });

  @override
  State<MultiImagePicker> createState() => _MultiImagePickerState();
}

class _MultiImagePickerState extends State<MultiImagePicker> {
  final ImagePicker _picker = ImagePicker();
  late List<XFile> _images;

  @override
  void initState() {
    super.initState();
    _images = List<XFile>.from(widget.initialImages);
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _images.add(picked);
      });
      widget.onChanged(_images);
    }
  }

  void _removeAt(int index) {
    setState(() {
      _images.removeAt(index);
    });
    widget.onChanged(_images);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _images.length; i++)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_images[i].path),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _removeAt(i),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  )
                ],
              ),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: const Center(child: Icon(Icons.add_a_photo, size: 28)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Add photos (tap + to add). Max recommended: 6',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
