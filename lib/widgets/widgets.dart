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
    required String label,
    String? assetIconPath, // <-- asset icon path
    double iconSize = 24.0,
    double size = 16.0,
    double height = 50.0,
    double width = 130.0,
    Color backgroundColor = AppColors.buttonColor,
    Color textColor = AppColors.background,
    FontWeight fontWeight = FontWeight.bold,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton.icon(
        icon: assetIconPath != null
            ? Image.asset(assetIconPath, width: iconSize, height: iconSize)
            : const SizedBox.shrink(), // fallback if no icon is passed
        label: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: size,
            fontWeight: fontWeight,
          ),
        ),
        style: ElevatedButton.styleFrom(backgroundColor: backgroundColor),
        onPressed: onPressed,
      ),
    );
  }

  Widget commonText({
    required String text,
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.normal,
    Color color = Colors.black, // Replace with AppColors.primaryColor if needed
  }) {
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }

  static Widget AppRoundedIconButton({
    required VoidCallback onPressed,
    required String label,
    required String assetPath, // e.g. 'assets/icons/mic.png'
    double iconSize = 24.0,
    double fontSize = 16.0,
    double width = 220.0,
    double height = 50.0,
    Color borderColor = Colors.black87,
    Color textColor = Colors.black87,
    Color backgroundColor = Colors.transparent,
    FontWeight fontWeight = FontWeight.bold,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Image.asset(assetPath, width: iconSize, height: iconSize),
        label: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          side: BorderSide(color: borderColor, width: 2.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget commonTextField({
    TextEditingController? controller,
    String hintText = '',
    bool enabled = true,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onSubmitted,
    VoidCallback? onIconPressed,
    String? assetPath,
  }) {
    OutlineInputBorder _inputBorder(Color color, double width) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Colors.grey,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        enabledBorder: _inputBorder(Colors.grey, 1.0),
        focusedBorder: _inputBorder(AppColors.primaryColor, 2.0),
        suffixIcon: assetPath != null
            ? IconButton(
                icon: Image.asset(assetPath, width: 30, height: 30),
                onPressed: onIconPressed,
              )
            : null,
      ),
    );
  }
}
