import 'package:cukup/core/cap_rule.dart';
import 'package:cukup/core/pay_notif.dart';
import 'package:flutter_test/flutter_test.dart';

// The rules that decide what is a payment live in Kotlin (PaymentDetectTest.kt). These cover reading the list they produce.
void main() {
  const pay1 = '{"k":"pay","id":"a1","t":1000,"app":"TNG eWallet","kind":"wallet","title":"Paid","text":"You paid RM 5.00 to Mixue","cents":500,"shop":"Mixue"}';
  const pay2 = '{"k":"pay","id":"b2","t":2000,"app":"CIMB","kind":"bank","title":"","text":"RM 9.00 spent","cents":900}';
  const pay3 = '{"k":"pay","id":"c3","t":3000,"app":"HLB","kind":"bank","title":"","text":"RM 1.00 paid","cents":100}';
  const tap = '{"k":"pay","id":"d4","t":4000,"app":"Google Wallet","kind":"card","title":"WENG HOE","text":"MYR28.00 with AmBank Visa","cents":2800,"shop":"WENG HOE","card":"AmBank Visa"}';
  const skip = '{"k":"skip","t":1500,"app":"ShopeePay","kind":"wallet","title":"Sale","text":"9.9 is here"}';

  test('sorts what is waiting, what to save, and what is finished', () {
    final inbox = readInbox([pay1, skip, pay2, pay3, '{"k":"act","id":"a1","a":"save","via":"banner","t":4000}', '{"k":"act","id":"c3","a":"ignore","t":4100}', '{"k":"pa'].join('\n'), {});
    expect(inbox.pending.map((d) => d.id), ['b2']);
    expect(inbox.toSave.map((d) => d.id), ['a1']);
    expect(inbox.toSave.single.via, 'banner');
    expect(inbox.log.length, 4);
    expect(inbox.log.first.app, 'HLB'); // newest first
  });

  test('nothing is saved without a Save', () {
    final inbox = readInbox('$pay1\n$pay2\n$tap', {});
    expect(inbox.toSave, isEmpty);
    expect(inbox.pending.length, 3);
  });

  test('never offers something the app already dealt with', () {
    final inbox = readInbox('$pay1\n$pay2\n{"k":"act","id":"a1","a":"save","t":4000}', {'a1', 'b2'});
    expect(inbox.pending, isEmpty);
    expect(inbox.toSave, isEmpty);
  });

  test('entry details come from the detection', () {
    final d = readInbox(pay1, {}).pending.single;
    expect(d.merchant, 'Mixue');
    expect(d.paymentType({}), 'ewallet');
    expect(d.txnId, 'det-a1');
    expect(d.date, '1970-01-01');
    expect(d.time, '08:00'); // Malaysia time
    expect(readInbox(pay2, {}).pending.single.merchant, 'CIMB'); // no shop named: the app name
  });

  test('a card is asked about once, then remembered', () {
    final d = readInbox(tap, {}).pending.single;
    expect(d.paymentType({}), isNull); // new card: ask
    expect(d.paymentType({'ambank visa': 'credit_card'}), 'credit_card');
    final chosen = readInbox('$tap\n{"k":"act","id":"d4","a":"save","pay":"debit","via":"banner","t":5000}', {}).toSave.single;
    expect(chosen.paymentType({}), 'debit'); // picked on the banner
  });

  test('a second app reporting the same payment fills in the shop instead of adding a payment', () {
    final inbox = readInbox('$pay2\n{"k":"merge","id":"b2","t":2500,"app":"Google Wallet","shop":"KFC Kajang","card":"AmBank Visa"}', {});
    final d = inbox.pending.single;
    expect(d.merchant, 'KFC Kajang');
    expect(d.card, 'AmBank Visa');
    expect(d.alsoSeenBy, ['Google Wallet']);
    expect(inbox.renamed, isEmpty); // still waiting, nothing to fix up
    final later = readInbox('$pay2\n{"k":"merge","id":"b2","t":2500,"app":"Google Wallet","shop":"KFC Kajang"}', {'b2'});
    expect(later.renamed.single.merchant, 'KFC Kajang'); // already saved under "CIMB": rename it
  });

  test('categories decide what stays out of the weekly cap', () {
    setCapOff(['Bills', 'Utilities']);
    expect(capDefault('Utilities'), isFalse);
    expect(capDefault(' bills '), isFalse);
    expect(capDefault('Food'), isTrue);
    setCapOff(['Bills']); // back to the default for other tests
    expect(capDefault('Utilities'), isTrue);
  });
}
