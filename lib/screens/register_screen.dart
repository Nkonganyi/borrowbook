import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/app_logo.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final fullNameController = TextEditingController();
  final phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String role = 'seller';
  bool loading = false;
  bool obscurePassword = true;

  Future<void> register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      setState(() {
        loading = true;
      });

      await AuthService().register(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
        fullName: fullNameController.text.trim(),
        phone: phoneController.text.trim(),
        role: role,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registered. You can log in now.')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 48),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: "Full name",
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Phone",
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a phone number' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Choose a password' : null,
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Role", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, letterSpacing: 0.6)),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'seller', label: Text('Seller'), icon: Icon(Icons.storefront_outlined)),
                        ButtonSegment(value: 'buyer', label: Text('Buyer'), icon: Icon(Icons.person_outline)),
                      ],
                      selected: {role},
                      onSelectionChanged: (s) => setState(() => role = s.first),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: loading ? null : register,
                        child: loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text("Create account"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
