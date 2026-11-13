import 'package:cukup/core/pay_notif.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readPayment', () {
    test('reads money going out', () {
      expect(readPayment('wallet', 'Payment Successful', 'You have paid RM 12.50 to Mixue Kajang.'), 1250);
      expect(readPayment('bank', 'Transaction alert', 'RM1,234.00 was spent at AEON BIG on your card ending 1234'), 123400);
      expect(readPayment('bank', 'DuitNow', 'You transferred MYR 8 to KEDAI MAKAN ALI'), 800);
      expect(readPayment('wallet', 'Pembayaran berjaya', 'Pembayaran RM7.90 kepada 99 Speedmart'), 790);
    });

    test('ignores money coming in, codes, adverts and failures', () {
      expect(readPayment('wallet', 'Money received', 'You received RM 20.00 from Ali'), isNull);
      expect(readPayment('wallet', 'Reload', 'Reload of RM 50.00 successful'), isNull);
      expect(readPayment('bank', 'OTP', 'Your TAC for payment of RM 50.00 is 123456'), isNull);
      expect(readPayment('wallet', 'Cashback', 'You earned RM 0.50 cashback on your payment'), isNull);
      expect(readPayment('wallet', 'Vouchers', 'Pay with ShopeePay and get RM 5 off'), isNull);
      expect(readPayment('bank', 'Declined', 'Your payment of RM 30.00 was declined'), isNull);
      expect(readPayment('bank', 'Hello', 'Thanks for using our app'), isNull);
      expect(readPayment('wallet', 'Paid', 'Your payment went through'), isNull); // no amount
    });

    test('text messages count only when they are from a bank', () {
      expect(readPayment('sms', 'Ali', 'I paid RM 10 for lunch'), isNull);
      expect(readPayment('sms', 'CIMB', 'CIMB: RM 45.00 spent at SHELL on card 4321'), 4500);
    });
  });

  group('merchantFrom', () {
    test('finds the shop after to / at', () {
      expect(merchantFrom('Payment Successful', 'You have paid RM 12.50 to Mixue Kajang.'), 'Mixue Kajang');
      expect(merchantFrom('Transaction alert', 'RM1,234.00 was spent at AEON BIG on your card ending 1234'), 'AEON BIG');
      expect(merchantFrom('', 'Payment of RM5.00 to KK Mart via DuitNow QR'), 'KK Mart');
      expect(merchantFrom('', 'Pembayaran RM7.90 kepada 99 Speedmart berjaya'), '99 Speedmart');
    });

    test('gives up when the wording names no shop', () {
      expect(merchantFrom('Payment Successful', 'RM 12.50 has been deducted'), isNull);
      expect(merchantFrom('', 'You paid RM 3.00 to your account'), isNull);
    });
  });

  group('readInbox', () {
    const pay1 = '{"k":"pay","id":"a1","t":1000,"app":"TNG eWallet","kind":"wallet","title":"Paid","text":"You paid RM 5.00 to Mixue","cents":500}';
    const pay2 = '{"k":"pay","id":"b2","t":2000,"app":"CIMB","kind":"bank","title":"","text":"RM 9.00 spent at KFC","cents":900}';
    const pay3 = '{"k":"pay","id":"c3","t":3000,"app":"HLB","kind":"bank","title":"","text":"RM 1.00 paid","cents":100}';
    const skip = '{"k":"skip","t":1500,"app":"ShopeePay","kind":"wallet","title":"Sale","text":"9.9 is here"}';

    test('sorts what is waiting, what to save, and what is finished', () {
      final inbox = readInbox([pay1, skip, pay2, pay3, '{"k":"act","id":"a1","a":"save","t":4000}', '{"k":"act","id":"c3","a":"ignore","t":4100}', '{"k":"pa'].join('\n'), {});
      expect(inbox.pending.map((d) => d.id), ['b2']);
      expect(inbox.toSave.map((d) => d.id), ['a1']);
      expect(inbox.log.length, 4);
      expect(inbox.log.first.app, 'HLB'); // newest first
    });

    test('never offers something the app already dealt with', () {
      final inbox = readInbox('$pay1\n$pay2\n{"k":"act","id":"a1","a":"save","t":4000}', {'a1', 'b2'});
      expect(inbox.pending, isEmpty);
      expect(inbox.toSave, isEmpty);
    });

    test('entry details come from the detection', () {
      final d = readInbox(pay1, {}).pending.single;
      expect(d.merchant, 'Mixue');
      expect(d.paymentType, 'ewallet');
      expect(d.txnId, 'det-a1');
      expect(d.date, '1970-01-01');
      expect(d.time, '08:00'); // Malaysia time
    });
  });
}
