// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_application_1/constants/colors.dart';
// import 'package:flutter_application_1/widgets/widgets.dart';

// class RegisterScreen extends StatefulWidget {
//   const RegisterScreen({super.key});

//   @override
//   State<RegisterScreen> createState() => _RegisterScreenState();
// }

// class _RegisterScreenState extends State<RegisterScreen> {
//   final nameController = TextEditingController();
//   final emailController = TextEditingController();
//   final passwordController = TextEditingController();

//   void register() {
//     String name = nameController.text.trim();
//     String email = emailController.text.trim();
//     String password = passwordController.text;

//     if (name.isEmpty || email.isEmpty || password.isEmpty) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
//     } else {
//       FirebaseAuth.instance
//           .createUserWithEmailAndPassword(email: email, password: password)
//           .then((value) {
//             ScaffoldMessenger.of(
//               context,
//             ).showSnackBar(SnackBar(content: Text('Registered as $name')));
//             Navigator.pop(context);
//           });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.whitebackground,
//       appBar: AppBar(
//         title: const Text('Register'),
//         backgroundColor: AppColors.whitebackground,
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             CommonWidgets().commonTextField(
//               controller: nameController,
//               hintText: 'Full Name',
//             ),

//             const SizedBox(height: 16),

//             CommonWidgets().commonTextField(
//               controller: emailController,
//               hintText: 'Email',
//             ),
//             const SizedBox(height: 16),
//             CommonWidgets().commonTextField(
//               controller: passwordController,
//               hintText: 'Password',
//             ),

//             const SizedBox(height: 24),
//             ElevatedButton(onPressed: register, child: const Text('Register')),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_application_1/widgets/widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  void register() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Registered as $name')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            CommonWidgets().commonText(
              text: 'Full Name',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
            const SizedBox(height: 8),
            CommonWidgets().commonTextField(
              controller: nameController,
              hintText: 'Enter your full name',
            ),
            const SizedBox(height: 20),
            CommonWidgets().commonText(
              text: 'Email',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
            const SizedBox(height: 8),
            CommonWidgets().commonTextField(
              controller: emailController,
              hintText: 'Enter your email',
            ),
            const SizedBox(height: 20),
            CommonWidgets().commonText(
              text: 'Password',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
            const SizedBox(height: 8),
            CommonWidgets().commonTextField(
              controller: passwordController,
              hintText: 'Enter your password',
              obscureText: true,
            ),
            const SizedBox(height: 30),
            CommonWidgets.customButton(
              size: 18,
              fontWeight: FontWeight.bold,
              onPressed: register,
              label: 'Register',
            ),
          ],
        ),
      ),
    );
  }
}
