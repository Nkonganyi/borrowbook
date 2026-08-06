import 'package:flutter/material.dart';
import '../services/customer_service.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final locationController = TextEditingController();
  final notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool loading = false;

  Future<void> saveCustomer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      setState(() {
        loading = true;
      });

      final queuedOffline = await CustomerService().addCustomer(
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
        location: locationController.text.trim(),
        notes: notesController.text.trim(),
      );

      if (!mounted) return;

      Navigator.pop(context, queuedOffline ? 'queued' : true);
    } catch (e) {
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
    return Scaffold(
      appBar: AppBar(title: const Text("Add Customer")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: "Customer Name",
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the customer\'s name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Phone Number",
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: "Location",
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Notes",
                  prefixIcon: Icon(Icons.notes_rounded),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: loading ? null : saveCustomer,
                child: loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text("Save Customer"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
