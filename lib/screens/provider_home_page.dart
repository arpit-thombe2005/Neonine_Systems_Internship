import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/translation_service.dart';
import '../widgets/language_selector.dart';
import 'account_page.dart';

class ProviderHomePage extends StatefulWidget {
  const ProviderHomePage({super.key});

  @override
  State<ProviderHomePage> createState() => _ProviderHomePageState();
}

class _ProviderHomePageState extends State<ProviderHomePage>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final LocationService _locationService = LocationService();

  String _userName = 'User';
  String _currentLocation = 'Fetching location...';
  bool _isOnline = false;
  bool _isTogglingStatus = false;
  int _todayRequestCount = 0;
  bool _isLoadingRequests = false;
  List<Map<String, dynamic>> _requestsList = [];

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  Widget _buildStatusBadge(String status) {
    Color color;
    Color bgColor;

    switch (status.toLowerCase()) {
      case 'pending':
        color = const Color(0xFFFF9800);
        bgColor = const Color(0xFFFF9800).withOpacity(0.12);
        break;
      case 'accepted':
        color = const Color(0xFF4AE54A);
        bgColor = const Color(0xFF4AE54A).withOpacity(0.12);
        break;
      case 'rejected':
        color = const Color(0xFFFF4444);
        bgColor = const Color(0xFFFF4444).withOpacity(0.12);
        break;
      case 'completed':
        color = const Color(0xFF2196F3);
        bgColor = const Color(0xFF2196F3).withOpacity(0.12);
        break;
      default:
        color = Colors.white54;
        bgColor = Colors.white10;
    }

    String label;
    switch (status.toLowerCase()) {
      case 'pending':
        label = tr('status_pending');
        break;
      case 'accepted':
        label = tr('status_accepted');
        break;
      case 'rejected':
        label = tr('status_rejected');
        break;
      case 'completed':
        label = tr('status_completed');
        break;
      default:
        label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Future<void> _updateRequestStatus(String requestId, String status) async {
    try {
      final result = await _apiService.updateServiceRequestStatus(
        requestId: requestId,
        status: status,
      );
      if (result != null) {
        await _loadTodayRequests();
      }
    } catch (e) {
      debugPrint('Error updating request status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update request: ${e.toString().replaceAll('Exception:', '').trim()}',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: const Color(0xFFFF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _currentLocation = tr('fetching_location');
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();

    _loadUserData();
    _initLocation();
    _loadTodayRequests();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final name = await _authService.getUserName();
    final data = await _authService.getUserData();

    if (mounted) {
      setState(() {
        if (name != null) _userName = name;
        // Try to get online status from cached data
        if (data != null && data['is_online'] != null) {
          _isOnline = data['is_online'] == true;
        }
      });
    }
  }

  Future<void> _initLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (position != null) {
      final address = await _locationService.getAddressFromCoordinates(
          position.latitude, position.longitude);

      // Update location on server
      final userId = await _authService.getUserId();
      if (userId != null) {
        _apiService.updateLocation(
          userId: userId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      if (mounted) {
        setState(() {
          _currentLocation = address;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _currentLocation = 'Location unavailable';
        });
      }
    }
  }

  Future<void> _loadTodayRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      final userId = await _authService.getUserId();
      if (userId != null) {
        final count = await _apiService.getTodayRequestCount(userId);
        final requests = await _apiService.getTodayRequests(userId);
        if (mounted) {
          setState(() {
            _todayRequestCount = count;
            _requestsList = requests;
            _isLoadingRequests = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingRequests = false);
      }
    } catch (e) {
      debugPrint('Error loading requests: $e');
      if (mounted) setState(() => _isLoadingRequests = false);
    }
  }

  Future<void> _toggleOnlineStatus() async {
    if (_isTogglingStatus) return;

    setState(() => _isTogglingStatus = true);

    try {
      final userId = await _authService.getUserId();
      if (userId != null) {
        final newStatus = !_isOnline;
        await _apiService.toggleOnlineStatus(
          userId: userId,
          isOnline: newStatus,
        );

        // Update cached data
        await _authService.updateCachedUserData({'is_online': newStatus});

        if (mounted) {
          setState(() {
            _isOnline = newStatus;
            _isTogglingStatus = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling status: $e');
      if (mounted) {
        setState(() => _isTogglingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update status. Please try again.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _showChatBottomSheet(String requestId, String recipientName, String senderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final textController = TextEditingController();
        List<Map<String, dynamic>> messages = [];
        bool isLoadingChat = true;
        Timer? pollTimer;

        return StatefulBuilder(
          builder: (context, setChatState) {
            Future<void> fetchMessages() async {
              try {
                final list = await _apiService.getChatMessages(requestId);
                if (context.mounted) {
                  setChatState(() {
                    messages = list;
                    isLoadingChat = false;
                  });
                }
              } catch (e) {
                debugPrint('Error fetching chat messages: $e');
                if (context.mounted) {
                  setChatState(() => isLoadingChat = false);
                }
              }
            }

            // Setup polling every 3 seconds
            if (isLoadingChat) {
              fetchMessages();
              pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
                fetchMessages();
              });
            }

            return WillPopScope(
              onWillPop: () async {
                pollTimer?.cancel();
                return true;
              },
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.65,
                  decoration: const BoxDecoration(
                    color: Color(0xFF141414),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Pull indicator & Header
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chat with $recipientName',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54),
                            onPressed: () {
                              pollTimer?.cancel();
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10),

                      // Messages List
                      Expanded(
                        child: isLoadingChat
                            ? const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                                ),
                              )
                            : messages.isEmpty
                                ? Center(
                                    child: Text(
                                      'No messages yet. Send a message to start.',
                                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
                                    ),
                                  )
                                : ListView.builder(
                                    reverse: false,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) {
                                      final msg = messages[index];
                                      final isMe = msg['sender_id'] == senderId;
                                      final text = msg['message_text'] ?? '';
                                      final senderName = msg['sender_name'] ?? '';

                                      return Align(
                                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isMe ? const Color(0xFF4AE54A).withOpacity(0.12) : const Color(0xFF1E1E1E),
                                            borderRadius: BorderRadius.circular(16).copyWith(
                                              bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                                              bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
                                            ),
                                            border: Border.all(
                                              color: isMe ? const Color(0xFF4AE54A).withOpacity(0.3) : Colors.white.withOpacity(0.04),
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (!isMe)
                                                Text(
                                                  senderName,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(0xFF4AE54A),
                                                  ),
                                                ),
                                              const SizedBox(height: 2),
                                              Text(
                                                text,
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),

                      // Input Bar
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: TextField(
                                controller: textController,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(color: Colors.white24),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final text = textController.text.trim();
                              if (text.isEmpty) return;
                              textController.clear();
                              try {
                                await _apiService.sendChatMessage(
                                  requestId: requestId,
                                  senderId: senderId,
                                  messageText: text,
                                );
                                fetchMessages();
                              } catch (e) {
                                debugPrint('Error sending message: $e');
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showNotificationsSheet(String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        List<Map<String, dynamic>> notifications = [];
        bool isLoadingNotif = true;

        return StatefulBuilder(
          builder: (context, setNotifState) {
            Future<void> fetchNotifs() async {
              try {
                final list = await _apiService.getUserNotifications(userId);
                if (context.mounted) {
                  setNotifState(() {
                    notifications = list;
                    isLoadingNotif = false;
                  });
                }
              } catch (e) {
                debugPrint('Error fetching notifications: $e');
                if (context.mounted) {
                  setNotifState(() => isLoadingNotif = false);
                }
              }
            }

            if (isLoadingNotif) {
              fetchNotifs();
              _apiService.markNotificationsAsRead(userId);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Notifications Center',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: isLoadingNotif
                          ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                              ),
                            )
                          : notifications.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.notifications_none_rounded, color: Colors.white24, size: 48),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No notifications yet.',
                                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: notifications.length,
                                  itemBuilder: (context, index) {
                                    final n = notifications[index];
                                    final title = n['title'] ?? 'Notification';
                                    final msg = n['message'] ?? '';
                                    final isRead = n['is_read'] == true;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E1E),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            margin: const EdgeInsets.only(top: 3),
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: isRead ? Colors.transparent : const Color(0xFF4AE54A),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  msg,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: Colors.white54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showOfflineChannelsOverlay() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.cell_tower_rounded, color: Color(0xFF4AE54A), size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Offline Access Channels',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Farmers without active internet can request, check, or list agricultural services using these offline templates:',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white54, height: 1.4),
              ),
              const SizedBox(height: 20),
              
              _buildChannelGuide(
                title: 'IVR Voice Portal (Toll-Free)',
                details: 'Call 1800-3000-NEON (1800-3000-6366)\nFollow voice instructions to select equipment and book automatically in local languages.',
                icon: Icons.settings_phone_rounded,
              ),
              const SizedBox(height: 16),
              
              _buildChannelGuide(
                title: 'WhatsApp Automated Bot',
                details: 'Send "BOOK" to +91 90001 90002.\nOur automated assistant will guide you step-by-step through agricultural service booking.',
                icon: Icons.chat_rounded,
              ),
              const SizedBox(height: 16),
              
              _buildChannelGuide(
                title: 'SMS Booking Templates',
                details: 'SMS "BOOK <Category_ID> <Village_Name>" to 56767.\nExample: BOOK 1 Vasantpur\nCategory IDs: 1-Tractor, 2-Fertilizer, 4-Machinery Rental.',
                icon: Icons.sms_rounded,
              ),
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelGuide({required String title, required String details, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF4AE54A), size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white54, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEquipmentManagerSheet() async {
    final userId = await _authService.getUserId();
    if (userId == null) return;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        List<Map<String, dynamic>> equipmentList = [];
        bool isLoadingEq = true;
        
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> loadEq() async {
              try {
                final list = await _apiService.getEquipmentList(providerId: userId);
                setModalState(() {
                  equipmentList = list;
                  isLoadingEq = false;
                });
              } catch (e) {
                debugPrint('Error loading equipment: $e');
                setModalState(() => isLoadingEq = false);
              }
            }

            if (isLoadingEq) {
              loadEq();
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: const BoxDecoration(
                  color: Color(0xFF141414),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pull indicator
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'My Equipment Listing',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showAddEquipmentDialog(context, userId, () {
                            setModalState(() => isLoadingEq = true);
                          }),
                          icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4AE54A), size: 28),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Equipment List
                    Expanded(
                      child: isLoadingEq
                          ? const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                              ),
                            )
                          : equipmentList.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.agriculture_outlined, color: Colors.white24, size: 48),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No equipment listed yet.',
                                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: equipmentList.length,
                                  itemBuilder: (context, index) {
                                    final eq = equipmentList[index];
                                    final name = eq['name'] ?? '';
                                    final category = eq['category_name'] ?? 'Other';
                                    final price = eq['price_per_hour'] != null
                                        ? double.tryParse(eq['price_per_hour'].toString()) ?? 0.0
                                        : 0.0;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E1E),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: GoogleFonts.inter(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                category,
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: Colors.white38,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                '₹${price.toStringAsFixed(0)}/hr',
                                                style: GoogleFonts.inter(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(0xFF4AE54A),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              IconButton(
                                                onPressed: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      backgroundColor: const Color(0xFF1E1E1E),
                                                      title: Text(tr('remove_equipment'), style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                                                      content: Text(tr('confirm_remove_equipment'), style: GoogleFonts.inter(color: Colors.white70)),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, false),
                                                          child: Text(tr('cancel'), style: GoogleFonts.inter(color: Colors.white54)),
                                                        ),
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, true),
                                                          child: Text(tr('remove'), style: GoogleFonts.inter(color: const Color(0xFFFF4444), fontWeight: FontWeight.bold)),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    try {
                                                      final eqId = eq['id'];
                                                      if (eqId != null) {
                                                        await _apiService.deleteEquipment(eqId.toString());
                                                        setModalState(() {
                                                          isLoadingEq = true;
                                                        });
                                                      }
                                                    } catch (e) {
                                                      debugPrint('Error deleting equipment: $e');
                                                    }
                                                  }
                                                },
                                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4444), size: 20),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddEquipmentDialog(BuildContext context, String providerId, VoidCallback onAdded) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    int selectedCategoryId = 1; // Default Tractor
    bool isSaving = false;

    final categories = [
      {'id': 1, 'name': 'Tractor'},
      {'id': 2, 'name': 'Harvester'},
      {'id': 3, 'name': 'Rotavator'},
      {'id': 4, 'name': 'Seed Drill'},
      {'id': 5, 'name': 'Power Sprayer'},
      {'id': 6, 'name': 'Thresher'},
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF181818),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.08))),
              title: Text(
                'Add Equipment',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: GoogleFonts.inter(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Equipment Name (e.g. John Deere)',
                      hintStyle: GoogleFonts.inter(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<int>(
                    value: selectedCategoryId,
                    dropdownColor: const Color(0xFF1E1E1E),
                    style: GoogleFonts.inter(color: Colors.white),
                    isExpanded: true,
                    underline: Container(height: 1, color: Colors.white12),
                    items: categories.map((cat) {
                      return DropdownMenuItem<int>(
                        value: cat['id'] as int,
                        child: Text(tr(cat['name'] as String)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedCategoryId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Price per Hour (₹)',
                      hintStyle: GoogleFonts.inter(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty || priceController.text.trim().isEmpty) {
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            final price = double.tryParse(priceController.text) ?? 0.0;
                            await _apiService.addEquipment(
                              providerId: providerId,
                              name: nameController.text.trim(),
                              categoryId: selectedCategoryId,
                              pricePerHour: price,
                            );
                            onAdded();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            debugPrint('Error adding equipment: $e');
                            setDialogState(() => isSaving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4AE54A),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.black)))
                      : Text('Add', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.cell_tower_rounded, color: Colors.white70),
                      onPressed: _showOfflineChannelsOverlay,
                      tooltip: 'Offline channels info',
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70),
                          onPressed: () async {
                            final userId = await _authService.getUserId();
                            if (userId != null) {
                              _showNotificationsSheet(userId);
                            }
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(width: 12),
                        const LanguageSelector(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Top bar with online/offline toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tr('hello')} $_userName',
                            style: GoogleFonts.inter(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Color(0xFF4AE54A),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _currentLocation,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.white38,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Online/Offline toggle
                    GestureDetector(
                      onTap: _toggleOnlineStatus,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _isOnline
                              ? const Color(0xFF4AE54A).withOpacity(0.12)
                              : const Color(0xFFFF4444).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _isOnline
                                ? const Color(0xFF4AE54A).withOpacity(0.3)
                                : const Color(0xFFFF4444).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Status dot
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _isOnline
                                    ? const Color(0xFF4AE54A)
                                    : const Color(0xFFFF4444),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isOnline
                                            ? const Color(0xFF4AE54A)
                                            : const Color(0xFFFF4444))
                                        .withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOnline ? 'Online' : 'Offline',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _isOnline
                                    ? const Color(0xFF4AE54A)
                                    : const Color(0xFFFF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: MediaQuery.of(context).size.height * 0.06),

                // Status card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.07),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _isOnline
                            ? Icons.wifi_rounded
                            : Icons.wifi_off_rounded,
                        color: _isOnline
                            ? const Color(0xFF4AE54A)
                            : Colors.white24,
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isOnline
                            ? 'Your services are visible to farmers'
                            : 'You are offline. Toggle to go online.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white38,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Manage Equipment button
                GestureDetector(
                  onTap: _showEquipmentManagerSheet,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.07),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Equipment Listing',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to list & manage tractors/implements',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white24,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.agriculture_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Today's Requests button
                GestureDetector(
                  onTap: _loadTodayRequests,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.07),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('todays_requests'),
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to refresh',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white24,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _isLoadingRequests
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.white54),
                                  ),
                                )
                              : Text(
                                  '$_todayRequestCount',
                                  style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Requests Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${tr('todays_requests')}:',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    if (_requestsList.isNotEmpty)
                      Text(
                        '${_requestsList.length} items',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Requests List
                Expanded(
                  child: _isLoadingRequests
                      ? const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                            ),
                          ),
                        )
                      : _requestsList.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.inbox_outlined,
                                    color: Colors.white24,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    tr('no_requests'),
                                    style: GoogleFonts.inter(
                                      color: Colors.white30,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: _requestsList.length,
                              itemBuilder: (context, index) {
                                final request = _requestsList[index];
                                final farmerName = request['farmer_name'] ?? 'Farmer';
                                final farmerPhone = request['farmer_phone'] ?? '';
                                final message = request['message'] ?? '';
                                final status = request['status'] ?? 'pending';
                                final requestId = request['id'];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF111111),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.06),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top row: Farmer name & status badge
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              farmerName,
                                              style: GoogleFonts.inter(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildStatusBadge(status),
                                        ],
                                      ),

                                      // Phone number
                                      if (farmerPhone.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '+$farmerPhone',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: const Color(0xFF4AE54A),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],

                                      // Message
                                      if (message.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1A1A1A),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.04),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            message,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: Colors.white70,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],

                                      // Actions
                                      if (status.toLowerCase() == 'pending') ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () => _updateRequestStatus(requestId, 'rejected'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(0xFFFF4444),
                                                  side: BorderSide(
                                                    color: const Color(0xFFFF4444).withOpacity(0.4),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  tr('reject'),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () => _updateRequestStatus(requestId, 'accepted'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF4AE54A),
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  tr('approve'),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else if (status.toLowerCase() == 'accepted') ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: ElevatedButton(
                                                onPressed: () => _updateRequestStatus(requestId, 'completed'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  tr('complete'),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              flex: 1,
                                              child: OutlinedButton(
                                                onPressed: () async {
                                                  final myId = await _authService.getUserId();
                                                  if (myId != null) {
                                                    _showChatBottomSheet(
                                                      requestId,
                                                      farmerName,
                                                      myId,
                                                    );
                                                  }
                                                },
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  side: BorderSide(
                                                    color: Colors.white.withOpacity(0.12),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  'Chat',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),

      // Account floating button — bottom right
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, animation, __) => const AccountPage(),
              transitionsBuilder: (_, animation, __, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        },
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: const Icon(
          Icons.account_circle_outlined,
          color: Colors.white70,
          size: 28,
        ),
      ),
    );
  }
}
