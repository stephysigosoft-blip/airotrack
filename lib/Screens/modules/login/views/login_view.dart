import 'package:airotrack/Screens/widgets/auth_logo.dart';
import 'package:airotrack/Screens/widgets/auth_text_field.dart';
import 'package:airotrack/Utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/login_controller.dart';
import '../../../routes/app_routes.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width * 0.04;
    final formWidth = width - (horizontalPadding * 2);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.loginGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthLogo(),
                  SizedBox(height: height * 0.035),
                  Text(
                    'Hello!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: width * 0.06,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: height * 0.01),
                  Text(
                    'Please Sign In To Your Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: width * 0.035,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                  SizedBox(height: height * 0.06),
                  Center(
                    child: Obx(
                      () => AuthTextField(
                        controller: controller.phoneController,
                        hint: 'Enter your phone number, email or username',
                        keyboardType: TextInputType.emailAddress,
                        errorText: controller.phoneError.value,
                        width: formWidth,
                      ),
                    ),
                  ),
                  SizedBox(height: height * 0.025),
                  Center(
                    child: Obx(
                      () => AuthTextField(
                        controller: controller.passwordController,
                        hint: 'Enter your password',
                        obscureText: !controller.isPasswordVisible.value,
                        errorText: controller.passwordError.value,
                        width: formWidth,
                        suffixIcon: IconButton(
                          icon: Icon(
                            controller.isPasswordVisible.value
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.grey,
                          ),
                          onPressed: controller.togglePasswordVisibility,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Get.toNamed(Routes.FORGOT_PASSWORD),
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: width * 0.03,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: height * 0.035),
                  Center(
                    child: SizedBox(
                      height: height * 0.065,
                      width: formWidth,
                      child: ElevatedButton(
                        onPressed: controller.signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.buttonColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            width * 0.03,
                          ),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: width * 0.045,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                  // SizedBox(height: height * 0.05),
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.center,
                  //   children: [
                  //     Text(
                  //       "Don't have an account? ",
                  //       style: TextStyle(
                  //         color: Colors.black,
                  //         fontSize: width * 0.035,
                  //       ),
                  //     ),
                  //     GestureDetector(
                  //       onTap: () => Get.toNamed(Routes.REGISTER),
                  //       child: Text(
                  //         'Sign up',
                  //         style: TextStyle(
                  //           color: AppColors.white,
                  //           fontWeight: FontWeight.bold,
                  //           fontSize: width * 0.035,
                  //         ),
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  SizedBox(height: height * 0.025),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
