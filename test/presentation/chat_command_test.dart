import 'package:flutter_test/flutter_test.dart';
import 'package:dec_chat/presentation/utils/chat_command.dart';

void main() {
  group('ChatCommand Slash Command Parser', () {
    test('identifies slash commands correctly', () {
      expect(ChatCommand.isCommand('/msg alice hello'), isTrue);
      expect(ChatCommand.isCommand('/who'), isTrue);
      expect(ChatCommand.isCommand('hello world'), isFalse);
      expect(ChatCommand.isCommand(' /msg bob'), isTrue);
    });

    test('parses /msg command with target peer and message', () {
      final cmd = ChatCommand.parse('/msg peer123 hello there how are you?');
      expect(cmd.type, equals(ChatCommandType.privateMessage));
      expect(cmd.target, equals('peer123'));
      expect(cmd.argument, equals('hello there how are you?'));
      expect(cmd.errorMessage, isNull);

      // Missing argument error
      final errCmd = ChatCommand.parse('/msg peer123');
      expect(errCmd.errorMessage, isNotNull);
      expect(errCmd.errorMessage, contains('Usage: /msg <peerId> <message>'));
    });

    test('parses /who command', () {
      final cmd = ChatCommand.parse('/who');
      expect(cmd.type, equals(ChatCommandType.who));
      expect(cmd.errorMessage, isNull);
    });

    test('parses /slap command', () {
      final cmd = ChatCommand.parse('/slap bob');
      expect(cmd.type, equals(ChatCommandType.slap));
      expect(cmd.target, equals('bob'));
      expect(cmd.errorMessage, isNull);

      final errCmd = ChatCommand.parse('/slap');
      expect(errCmd.errorMessage, contains('Usage: /slap <peerId>'));
    });

    test('parses /ping command', () {
      final cmd = ChatCommand.parse('/ping peerABC');
      expect(cmd.type, equals(ChatCommandType.ping));
      expect(cmd.target, equals('peerABC'));
      expect(cmd.errorMessage, isNull);

      final errCmd = ChatCommand.parse('/ping');
      expect(errCmd.errorMessage, contains('Usage: /ping <peerId>'));
    });

    test('parses /join command and normalizes # prefix', () {
      final cmdWithHash = ChatCommand.parse('/join #9q8yy');
      expect(cmdWithHash.type, equals(ChatCommandType.join));
      expect(cmdWithHash.target, equals('#9q8yy'));

      final cmdWithoutHash = ChatCommand.parse('/join general');
      expect(cmdWithoutHash.type, equals(ChatCommandType.join));
      expect(cmdWithoutHash.target, equals('#general'));

      final errCmd = ChatCommand.parse('/join');
      expect(errCmd.errorMessage, contains('Usage: /join <#channel>'));
    });

    test('parses /clear, /panic, and /help commands', () {
      expect(ChatCommand.parse('/clear').type, equals(ChatCommandType.clear));
      expect(ChatCommand.parse('/panic').type, equals(ChatCommandType.panic));
      expect(ChatCommand.parse('/help').type, equals(ChatCommandType.help));
    });

    test('handles unknown command gracefully', () {
      final cmd = ChatCommand.parse('/unknownCommand');
      expect(cmd.type, equals(ChatCommandType.unknown));
      expect(cmd.errorMessage, contains('Unknown command'));
    });

    test('filters autocompletion suggestions matching query prefix', () {
      final mSuggestions = ChatCommand.getSuggestions('/m');
      expect(mSuggestions.length, equals(1));
      expect(mSuggestions.first.command, equals('/msg'));

      final pSuggestions = ChatCommand.getSuggestions('/p');
      expect(pSuggestions.length, equals(2)); // /ping, /panic

      final allSuggestions = ChatCommand.getSuggestions('/');
      expect(allSuggestions.length, equals(ChatCommand.availableSuggestions.length));

      final emptySuggestions = ChatCommand.getSuggestions('hello');
      expect(emptySuggestions.isEmpty, isTrue);
    });
  });
}
