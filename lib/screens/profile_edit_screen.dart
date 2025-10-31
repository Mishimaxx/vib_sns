import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../models/profile.dart';
import '../services/profile_interaction_service.dart';
import '../state/encounter_manager.dart';
import '../state/local_profile_loader.dart';
import '../state/profile_controller.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _homeTownController;
  late final TextEditingController _hobbiesController;
  bool _saving = false;
  String? _avatarImageBase64;
  Uint8List? _avatarImageBytes;
  bool _avatarRemoved = false;
  final ImagePicker _picker = ImagePicker();
  VoidCallback? _nameListener;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _bioController =
        TextEditingController(text: _initialValue(widget.profile.bio));
    _homeTownController =
        TextEditingController(text: _initialValue(widget.profile.homeTown));
    _hobbiesController =
        TextEditingController(text: widget.profile.favoriteGames.join('\n'));
    _avatarImageBase64 = widget.profile.avatarImageBase64;
    _avatarImageBytes = _decodeAvatar(widget.profile.avatarImageBase64);
    _nameListener = () => setState(() {});
    _nameController.addListener(_nameListener!);
  }

  @override
  void dispose() {
    if (_nameListener != null) {
      _nameController.removeListener(_nameListener!);
      _nameListener = null;
    }
    _nameController.dispose();
    _bioController.dispose();
    _homeTownController.dispose();
    _hobbiesController.dispose();
    super.dispose();
  }

  Uint8List? _decodeAvatar(String? base64) {
    if (base64 == null || base64.trim().isEmpty) {
      return null;
    }
    try {
      final bytes = base64Decode(base64.trim());
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  String _initialValue(String value) {
    if (value.trim().isEmpty) return '';
    if (value.trim() == '\u672a\u767b\u9332') return '';
    return value;
  }

  List<String> _parseHobbies(String raw) {
    if (raw.trim().isEmpty) return const <String>[];
    final parts = raw.split(RegExp(r'[\n,]'));
    final cleaned = <String>[];
    for (final part in parts) {
      final value = part.trim();
      if (value.isNotEmpty) {
        cleaned.add(value);
      }
    }
    return cleaned;
  }

  Future<void> _pickAvatar() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
      );
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _showSnack(
            '\u9078\u629e\u3057\u305f\u753b\u50cf\u304c\u7121\u52b9\u3067\u3057\u305f\u3002');
        return;
      }
      setState(() {
        _avatarImageBytes = bytes;
        _avatarImageBase64 = base64Encode(bytes);
        _avatarRemoved = false;
      });
    } catch (_) {
      _showSnack(
          '\u753b\u50cf\u306e\u8aad\u307f\u8fbc\u307f\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002');
    }
  }

  void _removeAvatar() {
    setState(() {
      _avatarImageBytes = null;
      _avatarImageBase64 = null;
      _avatarRemoved = true;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final displayName = _nameController.text.trim();
    final bio = _bioController.text.trim();
    final homeTown = _homeTownController.text.trim();
    final hobbies = _parseHobbies(_hobbiesController.text);

    final profileController = context.read<ProfileController>();
    final encounterManager = context.read<EncounterManager>();
    final interactionService = context.read<ProfileInteractionService>();
    final wasRunning = encounterManager.isRunning;

    try {
      final updated = await LocalProfileLoader.updateLocalProfile(
        displayName: displayName,
        bio: bio,
        homeTown: homeTown,
        favoriteGames: hobbies,
        avatarImageBase64: _avatarRemoved ? null : _avatarImageBase64,
        removeAvatarImage: _avatarRemoved,
      );
      await interactionService.bootstrapProfile(updated);
      profileController.updateProfile(updated, needsSetup: false);
      await encounterManager.switchLocalProfile(updated);
      if (wasRunning) {
        try {
          await encounterManager.start();
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      '\u3059\u308c\u9055\u3044\u3092\u518d\u8d77\u52d5\u3067\u304d\u307e\u305b\u3093\u3067\u3057\u305f: $error')),
            );
          }
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb\u306e\u4fdd\u5b58\u306b\u5931\u6557\u3057\u307e\u3057\u305f: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
            '\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb\u3092\u7de8\u96c6'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _handleSave,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('\u4fdd\u5b58'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    final currentName = _nameController.text.trim();
                    final displayNameForAvatar = currentName.isNotEmpty
                        ? currentName
                        : widget.profile.displayName;
                    final hasInitialAvatar =
                        widget.profile.avatarImageBase64?.trim().isNotEmpty ??
                            false;
                    final hasAvatar = !_avatarRemoved &&
                        (_avatarImageBytes != null || hasInitialAvatar);
                    return _AvatarEditor(
                      imageBytes: hasAvatar ? _avatarImageBytes : null,
                      fallbackColor: widget.profile.avatarColor,
                      displayName: displayNameForAvatar,
                      onPickImage: _pickAvatar,
                      onRemoveImage: hasAvatar ? _removeAvatar : null,
                      isSaving: _saving,
                    );
                  },
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: '\u8868\u793a\u540d',
                    hintText: '\u4f8b: \u3072\u306a\u305f',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return '\u540d\u524d\u3092\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044';
                    }
                    if (trimmed.length > 24) {
                      return '24\u6587\u5b57\u4ee5\u5185\u3067\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _bioController,
                  decoration: InputDecoration(
                    labelText: '\u4e00\u8a00\u30b3\u30e1\u30f3\u30c8',
                    hintText:
                        '\u3042\u306a\u305f\u306e\u30b9\u30c6\u30fc\u30bf\u30b9\u3084\u30b7\u30f3\u30d7\u30eb\u306a\u81ea\u5df1\u7d39\u4ecb',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.length > 120) {
                      return '120\u6587\u5b57\u4ee5\u5185\u306b\u3057\u3066\u304f\u3060\u3055\u3044';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _homeTownController,
                  decoration: InputDecoration(
                    labelText: '\u6d3b\u52d5\u30a8\u30ea\u30a2',
                    hintText:
                        '\u4f8b: \u6771\u4eac\u30a8\u30ea\u30a2 / \u95a2\u897f',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.length > 24) {
                      return '24\u6587\u5b57\u4ee5\u5185\u306b\u3057\u3066\u304f\u3060\u3055\u3044';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _hobbiesController,
                  decoration: InputDecoration(
                    labelText: '\u8da3\u5473',
                    hintText:
                        '\u6539\u884c\u307e\u305f\u306f\u30ab\u30f3\u30de\u533a\u5207\u308a\u3067\u8a18\u5165',
                    helperText:
                        '\u4f8b: \u30ab\u30d5\u30a7\u5de1\u308a / \u6620\u753b\u9451\u8cde / \u30dc\u30fc\u30c9\u30b2\u30fc\u30e0',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  maxLines: 5,
                  validator: (value) {
                    final hobbiesList = _parseHobbies(value ?? '');
                    if (hobbiesList.length > 8) {
                      return '\u8da3\u5473\u306f8\u500b\u307e\u3067\u8a18\u5165\u3067\u304d\u307e\u3059';
                    }
                    final longest = hobbiesList.fold<int>(
                        0,
                        (prev, element) =>
                            element.length > prev ? element.length : prev);
                    if (longest > 32) {
                      return '\u5404\u9805\u76ee\u306f32\u6587\u5b57\u4ee5\u5185\u306b\u3057\u3066\u304f\u3060\u3055\u3044';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _handleSave,
                    icon: const Icon(Icons.save_outlined),
                    label: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('\u4fdd\u5b58\u3057\u3066\u623b\u308b'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.imageBytes,
    required this.fallbackColor,
    required this.displayName,
    required this.onPickImage,
    this.onRemoveImage,
    required this.isSaving,
  });

  final Uint8List? imageBytes;
  final Color fallbackColor;
  final String displayName;
  final VoidCallback onPickImage;
  final VoidCallback? onRemoveImage;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initialsSource =
        displayName.trim().isEmpty ? '?' : displayName.trim();
    final initial = initialsSource.characters.first;
    final hasImage = imageBytes != null;
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: isSaving ? null : onPickImage,
            customBorder: const CircleBorder(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: fallbackColor,
                  backgroundImage: hasImage ? MemoryImage(imageBytes!) : null,
                  child: hasImage
                      ? null
                      : Text(
                          initial,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 3,
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 18,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: isSaving ? null : onPickImage,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('\u753b\u50cf\u3092\u9078\u3076'),
            ),
            if (onRemoveImage != null)
              TextButton.icon(
                onPressed: isSaving ? null : onRemoveImage,
                icon: const Icon(Icons.delete_outline),
                label: const Text('\u753b\u50cf\u3092\u524a\u9664'),
              ),
          ],
        ),
      ],
    );
  }
}
