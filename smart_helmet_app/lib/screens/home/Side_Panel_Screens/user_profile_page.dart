// lib/screens/home/Side_Panel_Screens/user_profile_page.dart
// User profile management screen — edit name, age, gender, height,
// weight, and emergency contacts (min 1, max 3).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_profile_provider.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isSaving = false;

  // Field controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _weightCtrl;
  String? _selectedGender;

  // Emergency contacts
  final List<Map<String, TextEditingController>> _contactControllers = [];

  @override
  void initState() {
    super.initState();
    final profile =
        Provider.of<UserProfileProvider>(context, listen: false);
    _nameCtrl = TextEditingController(text: profile.userName);
    _ageCtrl = TextEditingController(text: profile.age?.toString() ?? '');
    _heightCtrl =
        TextEditingController(text: profile.heightCm?.toString() ?? '');
    _weightCtrl =
        TextEditingController(text: profile.weightKg?.toString() ?? '');
    _selectedGender = profile.gender;

    // Pre-fill contacts
    for (final c in profile.emergencyContacts) {
      _contactControllers.add({
        'name': TextEditingController(text: c.name),
        'phone': TextEditingController(text: c.phone),
      });
    }

    // Ensure at least one empty contact row
    if (_contactControllers.isEmpty) {
      _addContactRow();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    for (final m in _contactControllers) {
      m['name']!.dispose();
      m['phone']!.dispose();
    }
    super.dispose();
  }

  void _addContactRow() {
    if (_contactControllers.length >= 3) return;
    setState(() {
      _contactControllers.add({
        'name': TextEditingController(),
        'phone': TextEditingController(),
      });
    });
  }

  void _removeContactRow(int index) {
    if (_contactControllers.length <= 1) return;
    setState(() {
      _contactControllers[index]['name']!.dispose();
      _contactControllers[index]['phone']!.dispose();
      _contactControllers.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate at least one contact has a phone number
    final filledContacts = _contactControllers
        .where((m) => m['phone']!.text.trim().isNotEmpty)
        .toList();
    if (filledContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please add at least one emergency contact number'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isSaving = true);

    final profile =
        Provider.of<UserProfileProvider>(context, listen: false);

    // Build contacts list from filled rows
    final contacts = filledContacts
        .map((m) => EmergencyContact(
              name: m['name']!.text.trim(),
              phone: m['phone']!.text.trim(),
            ))
        .toList();

    // Save each field
    await profile.updateProfileField('userName', _nameCtrl.text.trim());
    await profile.updateProfileField(
        'age', int.tryParse(_ageCtrl.text.trim()));
    await profile.updateProfileField('gender', _selectedGender);
    await profile.updateProfileField(
        'heightCm', double.tryParse(_heightCtrl.text.trim()));
    await profile.updateProfileField(
        'weightKg', double.tryParse(_weightCtrl.text.trim()));

    final err = await profile.updateEmergencyContacts(contacts);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isEditing = false;
    });

    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Profile saved successfully'),
        backgroundColor: Color(0xFF34C759),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ $err'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileProvider>();
    final bmi = profile.bmi;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isEditing)
            TextButton.icon(
              icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
              label: const Text('Edit',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isEditing)
            TextButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
              label: Text(_isSaving ? 'Saving…' : 'Save',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              onPressed: _isSaving ? null : _save,
            ),
        ],
      ),
      body: profile.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── BMI Card ──────────────────────────────────────────
                    if (bmi != null) _buildBmiCard(bmi),
                    if (bmi != null) const SizedBox(height: 20),

                    // ── Profile Info ──────────────────────────────────────
                    _sectionHeader('Personal Information'),
                    const SizedBox(height: 12),
                    _buildCard(children: [
                      _buildField(
                        label: 'Full Name',
                        controller: _nameCtrl,
                        icon: Icons.person_outline,
                        enabled: _isEditing,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        label: 'Age',
                        controller: _ageCtrl,
                        icon: Icons.calendar_today_outlined,
                        keyboardType: TextInputType.number,
                        enabled: _isEditing,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final a = int.tryParse(v.trim());
                          if (a == null || a < 10 || a > 120)
                            return 'Enter valid age';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _isEditing
                          ? DropdownButtonFormField<String>(
                              value: _selectedGender,
                              decoration: _decor('Gender', Icons.wc_outlined),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Male', child: Text('Male')),
                                DropdownMenuItem(
                                    value: 'Female', child: Text('Female')),
                                DropdownMenuItem(
                                    value: 'Other', child: Text('Other')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedGender = v),
                              validator: (v) =>
                                  v == null ? 'Select gender' : null,
                            )
                          : _readonlyTile('Gender', _selectedGender ?? '—',
                              Icons.wc_outlined),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: _buildField(
                            label: 'Height (cm)',
                            controller: _heightCtrl,
                            icon: Icons.straighten_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            enabled: _isEditing,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Required';
                              final h = double.tryParse(v.trim());
                              if (h == null || h < 100 || h > 250)
                                return '100–250 cm';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            label: 'Weight (kg)',
                            controller: _weightCtrl,
                            icon: Icons.monitor_weight_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            enabled: _isEditing,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Required';
                              final w = double.tryParse(v.trim());
                              if (w == null || w < 30 || w > 300)
                                return '30–300 kg';
                              return null;
                            },
                          ),
                        ),
                      ]),
                    ]),

                    const SizedBox(height: 24),

                    // ── Emergency Contacts ────────────────────────────────
                    Row(
                      children: [
                        _sectionHeader('Emergency Contacts'),
                        const Spacer(),
                        if (_isEditing && _contactControllers.length < 3)
                          TextButton.icon(
                            icon: const Icon(Icons.add_circle_outline,
                                size: 18),
                            label: const Text('Add'),
                            onPressed: _addContactRow,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Min 1 · Max 3 contacts. Alerts are sent to these numbers.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),

                    ..._contactControllers.asMap().entries.map((entry) {
                      final i = entry.key;
                      final m = entry.value;
                      return _buildContactCard(
                        index: i,
                        nameCtrl: m['name']!,
                        phoneCtrl: m['phone']!,
                      );
                    }),

                    const SizedBox(height: 32),

                    // Completion status
                    if (!profile.isProfileComplete)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFFFD700), width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: Color(0xFF856404), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Add at least one emergency contact to complete your profile. '
                                'Emergency alerts need this information.',
                                style: TextStyle(
                                  color: const Color(0xFF856404),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildBmiCard(double bmi) {
    final Color bmiColor;
    final String bmiLabel;
    if (bmi < 18.5) {
      bmiColor = const Color(0xFF007AFF);
      bmiLabel = 'Underweight';
    } else if (bmi < 25) {
      bmiColor = const Color(0xFF34C759);
      bmiLabel = 'Normal weight';
    } else if (bmi < 30) {
      bmiColor = const Color(0xFFFF9500);
      bmiLabel = 'Overweight';
    } else {
      bmiColor = const Color(0xFFFF3B30);
      bmiLabel = 'Obese';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bmiColor, bmiColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Body Mass Index',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                bmi.toStringAsFixed(1),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900),
              ),
              Text(
                bmiLabel,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.monitor_weight_outlined,
              color: Colors.white54, size: 60),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required int index,
    required TextEditingController nameCtrl,
    required TextEditingController phoneCtrl,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF065aa7).withOpacity(0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF065aa7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Contact ${index + 1}',
                  style: const TextStyle(
                      color: Color(0xFF065aa7),
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
              const Spacer(),
              if (_isEditing && _contactControllers.length > 1)
                GestureDetector(
                  onTap: () => _removeContactRow(index),
                  child: const Icon(Icons.remove_circle_outline,
                      color: Colors.red, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: nameCtrl,
            enabled: _isEditing,
            decoration: _decor('Name (optional)', Icons.person_outline),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: phoneCtrl,
            enabled: _isEditing,
            keyboardType: TextInputType.phone,
            decoration: _decor('Phone Number', Icons.phone_outlined),
            validator: (v) {
              // Only validate if this is the first contact
              if (index == 0 && (v == null || v.trim().isEmpty)) {
                return 'At least one phone number required';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      decoration: _decor(label, icon),
      validator: validator,
    );
  }

  Widget _readonlyTile(String label, String value, IconData icon) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.indigo),
      title: Text(label,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(value,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
    );
  }

  InputDecoration _decor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: Color(0xFF1C1C1E),
      ),
    );
  }
}
