import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dec_chat/domain/enums/transport_medium.dart';
import 'package:dec_chat/presentation/models/chat_message.dart';
import 'package:dec_chat/presentation/models/peer_model.dart';
import 'package:dec_chat/presentation/theme/app_theme.dart';
import 'package:dec_chat/presentation/views/chat_screen.dart';
import 'package:dec_chat/presentation/views/conversation_list_screen.dart';
import 'package:dec_chat/presentation/widgets/app_drawer.dart';
import 'package:dec_chat/presentation/widgets/message_bubble.dart';
import 'package:dec_chat/presentation/widgets/safety_number_card.dart';
import 'package:dec_chat/presentation/widgets/transport_badge.dart';

void main() {
  group('Minimalist Custom UI Widgets', () {
    testWidgets('TransportBadge renders BLE Mesh and Nostr indicators', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TransportBadge(medium: TransportMedium.bleMesh, rssi: -65),
                TransportBadge(medium: TransportMedium.nostr),
              ],
            ),
          ),
        ),
      );

      expect(find.text('BLE -65 dBm'), findsOneWidget);
      expect(find.text('Nostr'), findsOneWidget);
      expect(find.byIcon(Icons.bluetooth), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('MessageBubble renders outgoing, incoming, and system messages', (tester) async {
      final outgoing = ChatMessage(
        id: '1',
        senderId: 'local',
        senderNickname: 'Me',
        content: 'Outgoing secret',
        timestamp: DateTime(2026, 1, 1, 12, 34),
        isOutgoing: true,
        isEncrypted: true,
        channelOrPeerId: 'peer1',
        deliveryStatus: MessageDeliveryStatus.delivered,
      );

      final incoming = ChatMessage(
        id: '2',
        senderId: 'peer1',
        senderNickname: 'Alice',
        content: 'Incoming public',
        timestamp: DateTime(2026, 1, 1, 12, 35),
        isOutgoing: false,
        isEncrypted: false,
        channelOrPeerId: '#mesh',
      );

      final system = ChatMessage.system(
        id: '3',
        content: 'System announcement',
        channelOrPeerId: '#mesh',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ListView(
              children: [
                MessageBubble(message: outgoing),
                MessageBubble(message: incoming),
                MessageBubble(message: system),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Outgoing secret'), findsOneWidget);
      expect(find.text('Incoming public'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('System announcement'), findsOneWidget);

      // Lock icon for E2EE message
      expect(find.byIcon(Icons.lock), findsOneWidget);
      // Double checkmark for delivered
      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('MessageBubble clusters correctly with BubblePosition', (tester) async {
      final msg = ChatMessage(
        id: '1',
        senderId: 'local',
        senderNickname: 'Me',
        content: 'Clustered message',
        timestamp: DateTime.now(),
        isOutgoing: true,
        channelOrPeerId: 'peer1',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(message: msg, position: BubblePosition.first),
                MessageBubble(message: msg, position: BubblePosition.middle),
                MessageBubble(message: msg, position: BubblePosition.last),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Clustered message'), findsNWidgets(3));
    });

    testWidgets('SafetyNumberCard displays 12 blocks and triggers verification toggle', (tester) async {
      var toggleCalled = false;
      final peer = PeerModel(
        peerId: 'alice_id',
        nickname: 'Alice',
        lastSeen: DateTime.now(),
        isVerified: false,
        safetyNumber: '11111 22222 33333 44444 55555 66666 77777 88888 99999 00000 12345 67890',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SafetyNumberCard(
              peer: peer,
              onToggleVerified: () => toggleCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Safety Number with Alice'), findsOneWidget);
      expect(find.text('11111'), findsOneWidget);
      expect(find.text('67890'), findsOneWidget);
      expect(find.text('Mark as Verified'), findsOneWidget);

      // Tap switch
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(toggleCalled, isTrue);
    });

    testWidgets('ConversationListScreen pumps and displays channels and navigation menu', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ConversationListScreen(),
          ),
        ),
      );
      await tester.pump();

      // Channels section
      expect(find.text('CHANNELS'), findsOneWidget);
      expect(find.text('#mesh'), findsOneWidget);
      expect(find.text('#general'), findsOneWidget);

      // Direct Messages section
      expect(find.text('DIRECT MESSAGES'), findsOneWidget);

      // Menu button is present, FAB is removed
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('ChatScreen sends message and displays message bubble', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatScreen(channelOrPeerId: '#mesh'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('#mesh'), findsOneWidget);
      expect(find.text('Public Mesh Channel'), findsOneWidget);

      // Enter text and send
      await tester.enterText(find.byType(TextField), 'Hello DecChat World!');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Hello DecChat World!'), findsOneWidget);
    });

    testWidgets('ChatScreen shows slash command popup when user types /', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChatScreen(channelOrPeerId: '#mesh'),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '/s');
      await tester.pump();

      // Autocomplete popup should show /slap
      expect(find.text('/slap'), findsOneWidget);
      expect(find.text('Slap a peer with a large trout'), findsOneWidget);
    });

    testWidgets('AppDrawer opens via hamburger menu and shows navigation and account tab', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ConversationListScreen(),
          ),
        ),
      );
      await tester.pump();

      // Tap hamburger menu icon
      expect(find.byIcon(Icons.menu), findsOneWidget);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer is now open
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Peers'), findsOneWidget);
      expect(find.text('Mesh Network Online'), findsOneWidget);

      // Bottom account tab is displayed with edit icon
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('AppDrawer calls onOpenEditProfile when account tab is tapped', (tester) async {
      var profileOpened = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              drawer: AppDrawer(
                onOpenEditProfile: () => profileOpened = true,
              ),
              body: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Tap bottom account tab
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(profileOpened, isTrue);
    });

    testWidgets('AppDrawer tapping Peers navigates to PeerDirectoryScreen', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ConversationListScreen(),
          ),
        ),
      );
      await tester.pump();

      // Open drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Tap 'Peers' item
      await tester.tap(find.text('Peers'));
      await tester.pumpAndSettle();

      // Peer Directory screen should be visible
      expect(find.text('Discovered Peers'), findsOneWidget);
    });
  });
}
