import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactSupportPage extends StatefulWidget {
  @override
  _ContactSupportPageState createState() => _ContactSupportPageState();
}

class _ContactSupportPageState extends State<ContactSupportPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  bool _isSending = false;

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    final uri = Uri.parse(
      'mailto:support@smarthelmet.slit.edu'
      '?subject=${Uri.encodeComponent(_subjectController.text.isEmpty ? "Support Query" : _subjectController.text)}'
      '&body=${Uri.encodeComponent(
        "Name: ${_nameController.text}\n\n"
        "${_messageController.text}"
      )}',
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening email client...')),
        );
      } else {
        throw 'Could not launch email';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email client. Please try again.')),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Support'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header branding
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.support_agent,
                    size: 80,
                    color: Colors.indigo.withOpacity(0.8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We\'re Here to Help',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.indigo,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Smart Helmet App Support',
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Contact Info Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Get in Touch',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.email, color: Colors.indigo),
                      title: const Text('Email Us'),
                      subtitle: const Text('support@smarthelmet.slit.edu'),
                      onTap: () => launchUrl(Uri.parse('mailto:support@smarthelmet.slit.edu')),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.school, color: Colors.indigo),
                      title: const Text('Project Team'),
                      subtitle: const Text('SLIIT University\nInformation Technology Department'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Support Form Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Us a Message',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Your Name (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) => null, // Optional field
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Subject (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.subject),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          labelText: 'Your Message',
                          hintText: 'Describe your issue or feedback...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.message),
                        ),
                        maxLines: 6,
                        validator: (value) =>
                            value!.trim().isEmpty ? 'Please enter a message' : null,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isSending ? null : _sendEmail,
                          child: _isSending
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'Send Message via Email',
                                  style: TextStyle(fontSize: 16, color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}