import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emergency_contact_editor_sheet.dart';
import '../services/emergency_contacts_service.dart';
import '../ui_components.dart';
import 'home_screen.dart';

class EmergencyContactsSetupScreen extends StatefulWidget {
  const EmergencyContactsSetupScreen({super.key});

  @override
  State<EmergencyContactsSetupScreen> createState() =>
      _EmergencyContactsSetupScreenState();
}

class _EmergencyContactsSetupScreenState
    extends State<EmergencyContactsSetupScreen> {
  final _service = EmergencyContactsService();
  bool _isLoading = true;
  bool _isSaving = false;
  List<EmergencyContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await _service.getContacts();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _isLoading = false;
    });
  }

  Future<void> _openContactSheet({EmergencyContact? contact}) async {
    final didSave = await showEmergencyContactEditorSheet(
      context,
      contact: contact,
      suggestPrimary: _contacts.isEmpty,
      currentUserUid: FirebaseAuth.instance.currentUser?.uid,
      existingContacts: _contacts,
      onSave: _service.saveContact,
    );
    if (!mounted || !didSave) return;
    await _loadContacts();
  }

  Future<void> _setLater() async {
    setState(() => _isSaving = true);
    await _service.markOnboardingSkipped(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _continue() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add at least one contact or choose Set later.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    await _service.markOnboardingSkipped(false);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 2)),
    );
  }

  Future<void> _callContact(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not place the call.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      body: _isLoading
          ? const Center(
              child: AegixaLoader(),
            )
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add emergency contacts',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openContactSheet(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_contacts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No emergency contacts added yet.',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFA3A3A3)
                              : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    ..._contacts.map(
                      (contact) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EmergencyContactCard(
                          contact: contact,
                          onCall: () => _callContact(contact.phoneNumber),
                          onEdit: () => _openContactSheet(contact: contact),
                          onDelete: () async {
                            await _service.deleteContact(contact.id!);
                            await _loadContacts();
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  buildButton(
                    context: context,
                    label: 'Continue',
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : _continue,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _isSaving ? null : _setLater,
                    child: const Text('Set later'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EmergencyContactCard extends StatelessWidget {
  const _EmergencyContactCard({
    required this.contact,
    required this.onCall,
    required this.onEdit,
    required this.onDelete,
  });

  final EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  contact.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (contact.isPrimary)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Primary',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.phone_iphone, size: 18),
              const SizedBox(width: 8),
              Text(
                contact.phoneNumber,
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call'),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.more_vert,
                    color: theme.colorScheme.onSurface,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
