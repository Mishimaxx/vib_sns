import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _homeTownController.dispose();
    _hobbiesController.dispose();
    super.dispose();
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
    final wasRunning = encounterManager.isRunning;

    try {
      final updated = await LocalProfileLoader.updateLocalProfile(
        displayName: displayName,
        bio: bio,
        homeTown: homeTown,
        favoriteGames: hobbies,
      );
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
