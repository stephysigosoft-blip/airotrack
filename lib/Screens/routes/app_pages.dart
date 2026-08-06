import 'package:get/get.dart';
import '../modules/splash/bindings/splash_binding.dart';
import '../modules/splash/views/splash_view.dart';
import '../modules/welcome/bindings/welcome_binding.dart';
import '../modules/welcome/views/welcome_view.dart';
import '../modules/login/bindings/login_binding.dart';
import '../modules/login/views/login_view.dart';
import '../modules/register/bindings/register_binding.dart';
import '../modules/register/views/register_view.dart';
import '../modules/forgot_password/bindings/forgot_password_binding.dart';
import '../modules/forgot_password/views/forgot_password_view.dart';
import '../modules/otp_verification/bindings/otp_verification_binding.dart';
import '../modules/otp_verification/views/otp_verification_view.dart';
import '../modules/reset_password/bindings/reset_password_binding.dart';
import '../modules/reset_password/views/reset_password_view.dart';

import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/dashboard/bindings/dashboard_binding.dart';
import '../modules/dashboard/views/dashboard_view.dart';
import '../modules/notification/bindings/notification_binding.dart';
import '../modules/notification/views/notification_view.dart';
import '../modules/reminders/bindings/reminders_binding.dart';
import '../modules/reminders/views/reminders_view.dart';
import '../modules/reminders/bindings/add_reminder_binding.dart';
import '../modules/reminders/views/add_reminder_view.dart';
import '../modules/alerts/bindings/alerts_binding.dart';
import '../modules/alerts/views/alerts_view.dart';
import '../modules/statistics/bindings/statistics_binding.dart';
import '../modules/statistics/views/statistics_view.dart';
import '../modules/reports/bindings/reports_binding.dart';
import '../modules/reports/views/reports_view.dart';
import '../modules/reports/views/ignition_reports_view.dart';
import '../modules/reports/views/stoppage_reports_view.dart';
import '../modules/reports/views/trip_reports_view.dart';
import '../modules/reports/views/daily_reports_view.dart';
import '../modules/reports/views/summary_reports_view.dart';
import '../modules/reports/views/over_speed_reports_view.dart';
import '../modules/reports/views/geofence_reports_view.dart';
import '../modules/settings/bindings/settings_binding.dart';
import '../modules/settings/bindings/edit_profile_binding.dart';
import '../modules/settings/bindings/raise_ticket_binding.dart';
import '../modules/settings/bindings/add_expense_binding.dart';
import '../modules/settings/bindings/change_password_binding.dart';
import '../modules/settings/bindings/delete_account_binding.dart';
import '../modules/settings/bindings/general_settings_binding.dart';
import '../modules/settings/bindings/geofence_binding.dart';
import '../modules/settings/views/edit_profile_view.dart';
import '../modules/settings/views/raise_ticket_view.dart';
import '../modules/settings/views/support_ticket_view.dart';
import '../modules/settings/views/change_password_view.dart';
import '../modules/settings/views/configure_alerts_view.dart';
import '../modules/settings/views/expenses_view.dart';
import '../modules/settings/views/add_expense_view.dart';
import '../modules/settings/views/general_settings_view.dart';
import '../modules/settings/views/geofence_list_view.dart';
import '../modules/settings/views/settings_add_geofence_view.dart';
import '../modules/settings/views/delete_account_view.dart';
import '../modules/settings/views/delete_success_view.dart';
import '../modules/track/bindings/track_binding.dart';
import '../modules/track/views/track_view.dart';
import '../modules/track/views/add_geofence_view.dart';
import '../modules/track/views/add_location_picker_view.dart';
import '../modules/history/bindings/history_binding.dart';
import '../modules/history/views/history_view.dart';
import 'app_routes.dart';

class AppPages {
  static const INITIAL = Routes.SPLASH;

  static final routes = [
    GetPage(
      name: Routes.SPLASH,
      page: () => const SplashView(),
      binding: SplashBinding(),
    ),
    GetPage(
      name: Routes.WELCOME,
      page: () => const WelcomeView(),
      binding: WelcomeBinding(),
    ),
    GetPage(
      name: Routes.LOGIN,
      page: () => const LoginView(),
      binding: LoginBinding(),
    ),
    GetPage(
      name: Routes.REGISTER,
      page: () => const RegisterView(),
      binding: RegisterBinding(),
    ),
    GetPage(
      name: Routes.FORGOT_PASSWORD,
      page: () => const ForgotPasswordView(),
      binding: ForgotPasswordBinding(),
    ),
    GetPage(
      name: Routes.OTP_VERIFICATION,
      page: () => const OTPVerificationView(),
      binding: OTPVerificationBinding(),
    ),
    GetPage(
      name: Routes.RESET_PASSWORD,
      page: () => const ResetPasswordView(),
      binding: ResetPasswordBinding(),
    ),
    // Added a placeholder for HOME route
    GetPage(
      name: Routes.HOME,
      page: () => const HomeView(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: Routes.DASHBOARD,
      page: () => const DashboardView(),
      binding: DashboardBinding(),
    ),
    GetPage(
      name: Routes.NOTIFICATION,
      page: () => const NotificationView(),
      binding: NotificationBinding(),
    ),
    GetPage(
      name: Routes.REMINDERS,
      page: () => const RemindersView(),
      binding: RemindersBinding(),
    ),
    GetPage(
      name: Routes.ADD_REMINDER,
      page: () => const AddReminderView(),
      binding: AddReminderBinding(),
    ),
    GetPage(
      name: Routes.ALERTS,
      page: () => const AlertsView(),
      binding: AlertsBinding(),
    ),
    GetPage(
      name: Routes.STATISTICS,
      page: () => const StatisticsView(),
      binding: StatisticsBinding(),
    ),
    GetPage(
      name: Routes.REPORTS,
      page: () => const ReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.IGNITION_REPORTS,
      page: () => const IgnitionReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.STOPPAGE_REPORTS,
      page: () => const StoppageReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.TRIP_REPORTS,
      page: () => const TripReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.DAILY_REPORTS,
      page: () => const DailyReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.SUMMARY_REPORTS,
      page: () => const SummaryReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.OVER_SPEED_REPORTS,
      page: () => const OverSpeedReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.GEOFENCE_REPORTS,
      page: () => const GeofenceReportsView(),
      binding: ReportsBinding(),
    ),
    GetPage(
      name: Routes.EDIT_PROFILE,
      page: () => const EditProfileView(),
      binding: EditProfileBinding(),
    ),
    GetPage(
      name: Routes.RAISE_TICKET,
      page: () => const RaiseTicketView(),
      binding: RaiseTicketBinding(),
    ),
    GetPage(
      name: Routes.SUPPORT_TICKET,
      page: () => const SupportTicketView(),
      binding: SettingsBinding(),
    ),
    GetPage(
      name: Routes.CHANGE_PASSWORD,
      page: () => const ChangePasswordView(),
      binding: ChangePasswordBinding(),
    ),
    GetPage(
      name: Routes.CONFIGURE_ALERTS,
      page: () => const ConfigureAlertsView(),
    ),
    GetPage(
      name: Routes.EXPENSES,
      page: () => const ExpensesView(),
      binding: SettingsBinding(),
    ),
    GetPage(
      name: Routes.ADD_EXPENSE,
      page: () => const AddExpenseView(),
      binding: AddExpenseBinding(),
    ),
    GetPage(
      name: Routes.GENERAL_SETTINGS,
      page: () => const GeneralSettingsView(),
      binding: GeneralSettingsBinding(),
    ),
    GetPage(
      name: Routes.GEOFENCE,
      page: () => const GeofenceListView(),
      binding: GeofenceBinding(),
    ),
    GetPage(
      name: Routes.SETTINGS_ADD_GEOFENCE,
      page: () => const SettingsAddGeofenceView(),
      binding: GeofenceBinding(),
    ),
    GetPage(
      name: Routes.DELETE_ACCOUNT,
      page: () => const DeleteAccountView(),
      binding: DeleteAccountBinding(),
    ),
    GetPage(name: Routes.DELETE_SUCCESS, page: () => const DeleteSuccessView()),
    GetPage(
      name: Routes.TRACK,
      page: () => const TrackView(),
      binding: TrackBinding(),
    ),
    GetPage(
      name: Routes.ADD_GEOFENCE,
      page: () => const AddGeofenceView(),
      binding: TrackBinding(),
    ),
    GetPage(
      name: Routes.ADD_LOCATION_PICKER,
      page: () => const AddLocationPickerView(),
      binding: TrackBinding(),
    ),
    GetPage(
      name: Routes.HISTORY,
      page: () => HistoryView(imei: Get.parameters['imei']),
      binding: HistoryBinding(),
    ),
  ];
}
