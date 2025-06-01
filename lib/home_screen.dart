import 'package:flutter/material.dart';
import 'package:flutter_application_1/ai/heyGen_interactive_avatar.dart';
import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_application_1/constants/images.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        title: Text(
          "Dr.E",
          style: TextStyle(
            color: AppColors.background,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: Center(child: Text('Welcome to Dr.E')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const HeyGenHomePage()),
          );
          print('Floating Action Button Pressed');
        },
        backgroundColor: Colors
            .transparent, // or AppColors.buttonColor if you want a background
        elevation: 4, // optional, for shadow
        child: ClipOval(
          child: Image.asset(AppAssets.appIcon2, fit: BoxFit.cover),
        ),
      ),

      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {
      //     Navigator.push(
      //       context,
      //       MaterialPageRoute(builder: (context) => const HeyGenHomePage()),
      //     );
      //     print('Floating Action Button Pressed');
      //   },
      //   child: Image.asset(
      //     fit: BoxFit.fill,
      //     AppAssets.appIcon,
      //     width: 55,
      //     height: 55,
      //   ),
      //   backgroundColor: AppColors.buttonColor, // Optional: customize color
      // ),
    );
  }
}
