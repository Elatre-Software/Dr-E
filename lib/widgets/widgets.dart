import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants/colors.dart';

class CommonWidgets {
  static Widget backButton({
    required VoidCallback onPressed,
    Color color = Colors.black,
    String? image,
  }) {
    return IconButton(
      icon: image != null && image.isNotEmpty
          ? Image.asset(image)
          : Icon(Icons.arrow_back, color: color),
      iconSize: 40.0,
      onPressed: onPressed,
    );
  }

  static Widget customButton({
    required VoidCallback? onPressed,
    String label = 'Button',
    double size = 16.0,
    // IconData icon = Icons.check,
    Color backgroundColor = AppColors.buttonColor,
    Color textColor = AppColors.primaryColor,
    fontWeight = FontWeight.bold,
  }) {
    return SizedBox(
      width: 160,
      height: 60,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: backgroundColor),
        onPressed: onPressed,
        // icon: Icon(icon, color: textColor),
        label: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: size,
            fontWeight: fontWeight,
          ),
        ),
      ),
    );
  }

  //TextField

  Widget commonTextField({
    TextEditingController? controller,
    String hintText = '',
    bool enabled = true,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onSubmitted,
  }) {
    OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(25),
      borderSide: BorderSide(color: color, width: width),
    );

    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        enabledBorder: _border(Colors.grey, 1.0),
        focusedBorder: _border(
          AppColors.primaryColor,
          2.0,
        ), // Replace with AppColors.primaryColor if needed
      ),
    );
  }

  //Back Button
}

//Usage example

//commonTextField(
//   controller: _textController,
//   hintText: 'Say or type something...',
//   onSubmitted: (_) => _sendText(),
// )

// CommonWidgets.customButton(
//   onPressed: () {
//     print('Button Pressed');
//   },
// );
