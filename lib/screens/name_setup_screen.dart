import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/encounter_manager.dart';
import '../state/local_profile_loader.dart';
import '../state/profile_controller.dart';

class NameSetupScreen extends StatefulWidget {
  const NameSetupScreen({super.key});

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final name = _controller.text.trim();
    try {
      await LocalProfileLoader.saveDisplayName(name);
      final updated = await LocalProfileLoader.loadOrCreate();
      if (!mounted) return;
      final manager = context.read<EncounterManager>();
      final profileController = context.read<ProfileController>();
      await manager.switchLocalProfile(updated);
      unawaited(manager.start());
      profileController.updateProfile(updated, needsSetup: false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u306f\u3058\u3081\u307e\u3057\u3066',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '\u3059\u308c\u9055\u3044\u3067\u8868\u793a\u3055\u308c\u308b\u304a\u540d\u524d\u3092\u6c7a\u3081\u307e\u3057\u3087\u3046\u3002\n\u5f8c\u304b\u3089\u30d7\u30ed\u30d5\u30a3\u30fc\u30eb\u3067\u5909\u66f4\u3067\u304d\u307e\u3059\u3002',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: '\u8868\u793a\u540d',
                    hintText: '\u4f8b: \u3072\u306a\u305f',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '\u540d\u524d\u3092\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044';
                    }
                    if (value.trim().length > 24) {
                      return '24\u6587\u5b57\u4ee5\u5185\u3067\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _handleSubmit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('\u306f\u3058\u3081\u308b'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
