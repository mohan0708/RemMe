// File: lib/pages/danger_zone_alerts_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

class DangerZoneAlertsPage extends StatefulWidget {
  final String alertId;
  final String patientName;
  final LatLng alertLocation;
  final DateTime alertTime;

  const DangerZoneAlertsPage({
    super.key,
    required this.alertId,
    required this.patientName,
    required this.alertLocation,
    required this.alertTime,
  });

  @override
  State<DangerZoneAlertsPage> createState() => _DangerZoneAlertsPageState();
}

class _DangerZoneAlertsPageState extends State<DangerZoneAlertsPage> {
  late final AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _playAlertSound();
  }

  Future<void> _playAlertSound() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/alert_sound.wav'));
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _openInGoogleMaps() async {
    final url =
        'https://www.google.com/maps/search/?api=1&query=${widget.alertLocation.latitude},${widget.alertLocation.longitude}';
    if (!await launchUrl(Uri.parse(url))) {
      print('❌ Could not launch Google Maps');
    }
  }

  void _markAsResolved(BuildContext context) async {
    try {
      // Get the patient UID from the alert document
      final alertDoc = await FirebaseFirestore.instance
          .collection('alerts')
          .doc(widget.alertId)
          .get();

      if (!alertDoc.exists) {
        throw Exception('Alert document not found');
      }

      final patientUid = alertDoc.data()?['patientUid'];
      if (patientUid == null) {
        throw Exception('Patient UID not found in alert document');
      }

      // Update the alert in the patient's collection
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(patientUid)
          .collection('alerts')
          .doc(widget.alertId)
          .update({'resolved': true});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Alert marked as resolved.')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      print('❌ Failed to mark as resolved: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update alert status.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Color scheme
    const Color primaryColor = Color(0xFF4169E1); // Royal Blue
    const Color accentColor = Color(0xFFFFD700); // Quicksand
    const Color darkColor = Color(0xFF191970); // Swan Wing
    const Color surfaceColor = Colors.white;

    return Scaffold(
      backgroundColor: surfaceColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        color: darkColor,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Danger Zone Alert',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: darkColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
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
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: primaryColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.patientName} left the safe zone!',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: darkColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Last seen at: ${widget.alertLocation.latitude.toStringAsFixed(5)}, ${widget.alertLocation.longitude.toStringAsFixed(5)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: darkColor.withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Triggered at: ${widget.alertTime.hour}:${widget.alertTime.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: darkColor.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: widget.alertLocation,
                          zoom: 16,
                        ),
                        markers: {
                          Marker(
                            markerId: const MarkerId('alert_location'),
                            position: widget.alertLocation,
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueBlue,
                            ),
                            infoWindow: const InfoWindow(title: 'Alert Location'),
                          ),
                        },
                        zoomControlsEnabled: false,
                        myLocationEnabled: false,
                        onMapCreated: (controller) {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _openInGoogleMaps,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, color: primaryColor),
                            const SizedBox(width: 8),
                            Text(
                              'Open in Google Maps',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: darkColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _markAsResolved(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Mark as Resolved',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: surfaceColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
