import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import '../test/danger_zone_test_page.dart';
import 'guardian_routine_list_page.dart';

// Pages
import 'alerts_log_page.dart';
import 'profile_page.dart';
import 'danger_zone_alerts_page.dart';
import 'danger_zone_setup_page.dart';
import 'live_patient_tracking_page.dart';
import 'add_patient_page.dart';
import 'guardian_routine_list_page.dart';

class GuardianDashboardPage extends StatefulWidget {
  const GuardianDashboardPage({super.key});
  String? get _selectedPatientUid => null; // Add getter for state comparison

  @override
  State<GuardianDashboardPage> createState() => _GuardianDashboardPageState();
}

class _GuardianDashboardPageState extends State<GuardianDashboardPage>
    with TickerProviderStateMixin {
  // State variables
  String? _selectedPatientUid;
  List<Map<String, dynamic>> _linkedPatients = [];
  bool _isLoading = false;
  bool _hasUnresolvedAlerts = false;
  final TextEditingController _searchController = TextEditingController();
  int remembered = 0;
  int forgotten = 0;
  double rememberedPercent = 0;
  double forgottenPercent = 0;

  Future<void> _loadMemoryStats(String patientUid) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientUid)
          .collection('memory_stats')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        setState(() {
          remembered = data['remembered'] ?? 0;
          forgotten = data['forgotten'] ?? 0;
          final total = remembered + forgotten;
          rememberedPercent = total > 0 ? (remembered / total) * 100 : 0;
          forgottenPercent = total > 0 ? (forgotten / total) * 100 : 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading memory stats: $e');
    }
  }

  // Animation and audio
  late final AnimationController _animationController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _unresolvedAlertSub;

  // Color Scheme
  static const Color primaryColor = Color(0xFF4169E1); // Royal Blue
  static const Color primaryDark = Color(0xFF191970); // Swan Wing
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color surfaceColor = Colors.white;
  static const Color textPrimary = Color(0xFF191970); // Swan Wing
  static const Color textSecondary = Color(0xFF4169E1); // Royal Blue
  static const Color accentColor = Color(0xFFFFD700); // Quicksand
  static const LinearGradient gradientBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF5F5F5),
      Color(0xFFF0F0F0),
    ],
  );

  // Modern Text Styles
  final TextStyle headingStyle = const TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
    fontFamily: 'Roboto',
  );

  final TextStyle subheadingStyle = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    height: 1.5,
    fontFamily: 'Roboto',
  );

  final TextStyle labelStyle = const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    fontFamily: 'Roboto',
    letterSpacing: 0.1,
  );

  final TextStyle buttonTextStyle = const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    fontFamily: 'Roboto',
    letterSpacing: 0.5,
  );

  // Card Decoration
  BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceColor,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // Input Decoration
  InputDecoration get inputDecoration => InputDecoration(
    filled: true,
    fillColor: Colors.white,
    hintStyle: subheadingStyle.copyWith(color: textSecondary.withOpacity(0.6)),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _loadLinkedPatients();
    _setupFirebaseMessaging();
    _loadLastSelectedPatient();
  }

  @override
  void didUpdateWidget(GuardianDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedPatientUid != null && _selectedPatientUid != oldWidget._selectedPatientUid) {
      _loadMemoryStats(_selectedPatientUid!);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioPlayer.dispose();
    _unresolvedAlertSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLinkedPatients() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('guardians')
              .doc(user.uid)
              .collection('linkedPatients')
              .get();

      setState(() {
        _linkedPatients =
            querySnapshot.docs
                .map(
                  (doc) => {
                    'uid': doc.id,
                    'name': doc.data()['name'] ?? 'Unknown',
                    'photoUrl': doc.data()['photoUrl'] ?? '',
                  },
                )
                .toList();

        if (_linkedPatients.isNotEmpty && _selectedPatientUid == null) {
          _selectedPatientUid = _linkedPatients.first['uid'];
        }
      });
    } catch (e) {
      debugPrint('Error loading linked patients: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadLastSelectedPatient() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSelectedUid = prefs.getString('lastSelectedPatientUid');
    if (lastSelectedUid != null && mounted) {
      setState(() => _selectedPatientUid = lastSelectedUid);
    }
  }

  Future<void> _loadUnresolvedAlerts(String uid) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('patients')
          .doc(uid)
          .collection('alerts')
          .where('resolved', isEqualTo: false)
          .get();

      setState(() {
        _hasUnresolvedAlerts = snapshot.docs.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Error loading unresolved alerts: $e');
    }
  }

  void _onPatientSelected(String uid) {
    setState(() {
      _selectedPatientUid = uid;
      _saveLastSelectedPatient(uid);
    });
    _loadUnresolvedAlerts(uid);
    _loadMemoryStats(uid);
  }

  Future<void> _saveLastSelectedPatient(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastSelectedPatientUid', uid);
  }

  void _setupFirebaseMessaging() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Handle notification messages
      if (message.notification != null) {
        _showNotification(message.notification!);
      }

      // Handle data messages
      if (message.data.isNotEmpty) {
        if (message.data['type'] == 'danger_zone') {
          _handleDangerZoneAlert(message);
        }
      }
    });

    _watchUnresolvedAlerts();
  }

  void _watchUnresolvedAlerts() {
    _unresolvedAlertSub = FirebaseFirestore.instance
        .collection('alerts')
        .where('resolved', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            setState(() => _hasUnresolvedAlerts = snapshot.docs.isNotEmpty);
          }
        });
  }

  void _showNotification(RemoteNotification notification) {
    if (!mounted) return;

    // Show regular notification
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notification.body ?? 'New notification'),
          backgroundColor: primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _handleDangerZoneAlert(RemoteMessage message) async {
    try {
      final data = message.data;
      final patientId = data['patientId'];

      // Get patient details
      final patientDoc =
          await FirebaseFirestore.instance
              .collection('patients')
              .doc(patientId)
              .get();

      if (!patientDoc.exists) return;

      // Play alert sound
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/alert_sound.wav'));

      // Show full-screen alert
      if (!mounted) return;

      final locationData = data['location']!.split(',');
      final location = LatLng(
        double.parse(locationData[0]),
        double.parse(locationData[1]),
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => DangerZoneAlertsPage(
              alertId: data['alertId']!,
              patientName: patientDoc['name'] ?? 'Patient',
              alertLocation: location,
              alertTime: DateTime.parse(data['timestamp']!),
            ),
      );
    } catch (e) {
      debugPrint('Error handling danger zone alert: $e');
    }
  }

  void _showNoPatientError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Please select a patient first'),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  // Build the notification button in app bar
  Widget _buildNotificationButton() {
    return IconButton(
      icon: Stack(
        children: [
          const Icon(
            Icons.notifications_outlined,
            color: textPrimary,
            size: 24,
          ),
          if (_hasUnresolvedAlerts)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: surfaceColor, width: 2),
                ),
              ),
            ),
        ],
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AlertsLogPage()),
        );
      },
    );
  }

  // Build the profile button in app bar
  Widget _buildProfileButton() {
    return IconButton(
      icon: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_outline_rounded,
          color: primaryColor,
          size: 20,
        ),
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfilePage(profileData: {}),
          ),
        );
      },
    );
  }

  // Build welcome section with greeting and date
  Widget _buildWelcomeSection() {
    final now = DateTime.now();
    final formatter = DateFormat('EEEE, MMMM d');
    final greeting = _getGreeting();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                greeting,
                style: headingStyle.copyWith(
                  color: primaryDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  formatter.format(now),
                  style: subheadingStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Get appropriate greeting based on time of day
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // Build search and patient dropdown
  Widget _buildSearchAndDropdown(List<Map<String, dynamic>> filteredPatients) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Patient',
            style: labelStyle.copyWith(
              color: textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPatientUid,
                isExpanded: true,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 24,
                  color: textSecondary,
                ),
                hint: Text(
                  'Select a patient',
                  style: subheadingStyle.copyWith(
                    color: textSecondary.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
                items: filteredPatients.map((patient) {
                  return DropdownMenuItem<String>(
                    value: patient['uid'],
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: primaryColor.withOpacity(0.1),
                            child: Icon(Icons.person, color: primaryColor),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            patient['name'],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedPatientUid = newValue;
                      _saveLastSelectedPatient(newValue);
                    });
                  }
                },
                dropdownColor: surfaceColor,
                elevation: 2,
                borderRadius: BorderRadius.circular(16),
                menuMaxHeight: 300,
                style: subheadingStyle.copyWith(color: textPrimary, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Feature items list with modern colors
  final List<Map<String, dynamic>> _featureItems = [
    {
      'icon': Icons.calendar_today_rounded,
      'label': 'Routines',
      'color': const Color(0xFF4CAF50),
    },
    {
      'icon': Icons.location_on_rounded,
      'label': 'Live Tracking',
      'color': const Color(0xFF9C27B0),
    },
    {
      'icon': Icons.dangerous_rounded,
      'label': 'Danger Zones',
      'color': const Color(0xFFF44336),
    },

  ];

  // Handle feature tap
  void _onFeatureTapped(int index) {
    if (_selectedPatientUid == null) {
      _showNoPatientError();
      return;
    }

    switch (index) {
      case 0: // Routines
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GuardianRoutineListPage(
              patientUid: _selectedPatientUid!,
              patientName: _linkedPatients.firstWhere(
                (p) => p['uid'] == _selectedPatientUid,
                orElse: () => {'name': 'Patient'},
              )['name'] ?? 'Patient',
            ),
          ),
        );
        break;

      case 1: // Live Tracking
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    LivePatientTrackingPage(patientUid: _selectedPatientUid!),
          ),
        );
        break;

      case 2: // Danger Zones
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) =>
                    DangerZoneSetupPage(patientUid: _selectedPatientUid!),
          ),
        );
        break;
    }
  }

  // Build feature buttons grid with modern cards
  Widget _buildStatCard(String title, String value, String percentage, IconData icon, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: labelStyle.copyWith(
                    color: textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: headingStyle.copyWith(
                color: textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              percentage,
              style: labelStyle.copyWith(
                color: iconColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              'Features',
              style: labelStyle.copyWith(
                fontSize: 15,
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_selectedPatientUid != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatCard(
                        'Remembered',
                        '$remembered',
                        '${rememberedPercent.toStringAsFixed(0)}%',
                        Icons.check_circle,
                        Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        'Forgotten',
                        '$forgotten',
                        '${forgottenPercent.toStringAsFixed(0)}%',
                        Icons.cancel,
                        Colors.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _featureItems.length,
            itemBuilder: (context, index) {
              final item = _featureItems[index];
              return _buildFeatureCard(
                icon: item['icon'],
                label: item['label'],
                color: item['color'],
                onTap: () => _onFeatureTapped(index),
              );
            },
          ),
        ],
      ),
    );
  }

  // Build individual feature card with hover effect
  Widget _buildFeatureCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      label,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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

  @override
  Widget build(BuildContext context) {
    final filteredPatients =
        _linkedPatients.where((patient) {
          return patient['name'].toString().toLowerCase().contains(
            _searchController.text.toLowerCase(),
          );
        }).toList();

    final testButton =
        kDebugMode
            ? Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'test_button',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DangerZoneTestPage(),
                    ),
                  );
                },
                backgroundColor: Colors.red,
                child: const Icon(Icons.warning, color: Colors.white),
              ),
            )
            : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: surfaceColor,
        foregroundColor: textPrimary,
        centerTitle: false,
        title: Text(
          'Dashboard',
          style: headingStyle.copyWith(color: textPrimary, fontSize: 22),
        ),
        actions: [_buildNotificationButton(), _buildProfileButton()],
      ),

      body: Stack(
        children: [
          if (_isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: subheadingStyle.copyWith(
                      color: textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          else
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeSection(),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildSearchAndDropdown(filteredPatients),
                        ),
                        const SizedBox(width: 16),
                        FloatingActionButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AddPatientPage(),
                              ),
                            );
                          },
                          backgroundColor: primaryColor,
                          child: const Icon(Icons.person_add, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildFeatureButtons(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          if (kDebugMode) testButton,
        ],
      ),
    );
  }
}
