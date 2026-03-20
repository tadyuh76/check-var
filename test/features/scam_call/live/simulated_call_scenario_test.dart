import 'package:check_var/features/scam_call/live/simulated_call_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preset simulated call scripts are written in Vietnamese', () {
    expect(
      SimulatedCallScenario.safeCall.spokenScript,
      'Chào bạn, tôi muốn xác nhận bữa tối lúc bảy giờ tối nay. '
      'Nghe ổn đó. Tôi sẽ mang tài liệu vào ngày mai. '
      'Tuyệt, hẹn gặp bạn nhé.',
    );
    expect(
      SimulatedCallScenario.bankScam.spokenScript,
      'Đây là bộ phận chống gian lận của ngân hàng. '
      'Tài khoản của bạn sẽ bị khóa hôm nay nếu bạn không hành động ngay. '
      'Hãy chuyển tiền ngay lập tức để bảo vệ tài khoản.',
    );
    expect(
      SimulatedCallScenario.deliveryScam.spokenScript,
      'Gói hàng của bạn đang bị giữ tại hải quan. '
      'Bạn cần trả phí thông quan ngay bây giờ. '
      'Hãy gửi khoản thanh toán và đọc cho tôi mã xác nhận.',
    );
  });
}
