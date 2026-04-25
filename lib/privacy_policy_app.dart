import 'package:flutter/material.dart';

class PrivacyPolicyApp extends StatelessWidget {
  const PrivacyPolicyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Privacy Policy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E7490),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        useMaterial3: true,
      ),
      home: const PrivacyPolicyScreen(),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy Policy',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        context,
                        title: '',
                        body:
                            'Rastgele respects your privacy.',
                      ),
                      _section(
                        context,
                        title: 'Information We Collect',
                        body:
                            'We may collect basic user information such as name, location, and content you create, such as posts and photos, to provide app functionality.',
                      ),
                      _listSection(
                        context,
                        title: 'How We Use Information',
                        items: const [
                          'Provide core app features',
                          'Show and share fishing spots',
                          'Improve user experience',
                        ],
                      ),
                      _section(
                        context,
                        title: 'Location Data',
                        body:
                            'Rastgele may use location data to show nearby fishing spots, display your position on the map, and improve location-based app functionality.',
                      ),
                      _section(
                        context,
                        title: 'User Content',
                        body:
                            'Users may upload posts, photos, and fishing spot information. This content is used inside the app to provide sharing and discovery features.',
                      ),
                      _section(
                        context,
                        title: 'Data Sharing',
                        body:
                            'We do not sell or share your personal data with third parties.',
                      ),
                      _section(
                        context,
                        title: 'Security',
                        body:
                            'All data is transmitted securely using encryption.',
                      ),
                      _section(
                        context,
                        title: 'User Control',
                        body:
                            'You can request deletion of your account and associated data at any time.',
                      ),
                      _contactSection(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _listSection(
    BuildContext context, {
    required String title,
    required List<String> items,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• $item',
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contactSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contact',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'For privacy-related questions or data deletion requests, contact us at:',
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
        ),
        const SizedBox(height: 8),
        SelectableText(
          'contact@rastgelenetwork.com',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF0E7490),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
