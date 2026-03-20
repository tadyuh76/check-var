class SimulatedCallScenario {
  const SimulatedCallScenario({
    required this.title,
    required this.spokenScript,
  });

  factory SimulatedCallScenario.customScript(String transcript) {
    return SimulatedCallScenario(
      title: 'Custom Transcript',
      spokenScript: transcript.trim(),
    );
  }

  static const safeCall = SimulatedCallScenario(
    title: 'Safe Call',
    spokenScript:
        'Chào bạn, tôi muốn xác nhận bữa tối lúc bảy giờ tối nay. '
        'Nghe ổn đó. Tôi sẽ mang tài liệu vào ngày mai. '
        'Tuyệt, hẹn gặp bạn nhé.',
  );

  static const bankScam = SimulatedCallScenario(
    title: 'Bank Scam',
    spokenScript:
        'Đây là bộ phận chống gian lận của ngân hàng. '
        'Tài khoản của bạn sẽ bị khóa hôm nay nếu bạn không hành động ngay. '
        'Hãy chuyển tiền ngay lập tức để bảo vệ tài khoản.',
  );

  static const deliveryScam = SimulatedCallScenario(
    title: 'Delivery Scam',
    spokenScript:
        'Gói hàng của bạn đang bị giữ tại hải quan. '
        'Bạn cần trả phí thông quan ngay bây giờ. '
        'Hãy gửi khoản thanh toán và đọc cho tôi mã xác nhận.',
  );

  // --- Test scripts for accuracy verification ---

  static const safeCafe = SimulatedCallScenario(
    title: 'An toàn: Rủ cafe',
    spokenScript:
        'Ê tối nay rảnh không đi cafe đi. '
        'Mình mới tìm được quán mới ngon lắm. '
        'Khoảng bảy giờ mình qua đón nhé.',
  );

  static const safeParent = SimulatedCallScenario(
    title: 'An toàn: Mẹ gọi',
    spokenScript:
        'Con ơi chiều nay con đón em đi học về giúp mẹ nhé. '
        'Mẹ phải đi họp muộn. '
        'Tối mẹ nấu cơm cho cả nhà.',
  );

  static const safeDoctor = SimulatedCallScenario(
    title: 'An toàn: Gọi bác sĩ',
    spokenScript:
        'Dạ chào bác sĩ, tôi gọi để hỏi kết quả xét nghiệm của tôi hôm trước. '
        'Bác sĩ cho tôi biết khi nào tôi cần tái khám không ạ?',
  );

  static const fakePolice = SimulatedCallScenario(
    title: 'Lừa đảo: Giả công an',
    spokenScript:
        'Đây là công an quận ba. '
        'Số căn cước công dân của bạn liên quan đến một vụ án rửa tiền. '
        'Bạn cần chuyển toàn bộ tiền trong tài khoản sang tài khoản điều tra ngay bây giờ nếu không sẽ bị bắt.',
  );

  static const fakePrize = SimulatedCallScenario(
    title: 'Lừa đảo: Trúng thưởng',
    spokenScript:
        'Xin chúc mừng bạn đã trúng thưởng năm mươi triệu đồng từ chương trình khuyến mãi của Viettel. '
        'Để nhận thưởng bạn cần nộp hai triệu phí thuế trước.',
  );

  static const cryptoInvestment = SimulatedCallScenario(
    title: 'Lừa đảo: Đầu tư crypto',
    spokenScript:
        'Anh chị có muốn kiếm thêm thu nhập không? '
        'Sàn giao dịch Bitcoin mới mở, nạp mười triệu được tặng mười triệu. '
        'Lợi nhuận cam kết ba trăm phần trăm trong một tháng, rút tiền bất cứ lúc nào.',
  );

  static const kidnapping = SimulatedCallScenario(
    title: 'Lừa đảo: Dọa bắt cóc',
    spokenScript:
        'Nghe đây, chúng tôi đang giữ con gái bạn. '
        'Không được gọi công an. '
        'Chuyển hai trăm triệu vào số tài khoản tôi đọc ngay nếu muốn con bạn an toàn.',
  );

  static const fakeLoan = SimulatedCallScenario(
    title: 'Lừa đảo: Cho vay giả',
    spokenScript:
        'Bạn đã được duyệt khoản vay một trăm triệu lãi suất không phần trăm. '
        'Chỉ cần đóng năm trăm nghìn phí hồ sơ để giải ngân trong ngày hôm nay.',
  );

  static const fakeTechSupport = SimulatedCallScenario(
    title: 'Lừa đảo: Hỗ trợ kỹ thuật',
    spokenScript:
        'Tôi gọi từ bộ phận kỹ thuật Viettel. '
        'Điện thoại của bạn bị nhiễm virus rất nghiêm trọng. '
        'Bạn cần cài ứng dụng bảo mật theo đường link tôi gửi ngay và đóng ba trăm nghìn phí kích hoạt.',
  );

  static const romance = SimulatedCallScenario(
    title: 'Lừa đảo: Lừa tình',
    spokenScript:
        'Anh ơi em rất nhớ anh. '
        'Em cần hai mươi triệu để mua vé máy bay sang gặp anh mà em không có đủ tiền. '
        'Anh chuyển giúp em nhé, em sẽ trả lại ngay khi gặp.',
  );

  static const presets = [
    safeCall,
    bankScam,
    deliveryScam,
    safeCafe,
    safeParent,
    safeDoctor,
    fakePolice,
    fakePrize,
    cryptoInvestment,
    kidnapping,
    fakeLoan,
    fakeTechSupport,
    romance,
  ];

  final String title;
  final String spokenScript;

  List<String> get spokenLines => _splitTranscript(spokenScript);

  static List<String> _splitTranscript(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final lines = <String>[];
    for (final block in normalized.split(RegExp(r'[\r\n]+'))) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) {
        continue;
      }

      final matches = RegExp(r'[^.!?]+[.!?]?').allMatches(trimmedBlock);
      var addedSentence = false;
      for (final match in matches) {
        final sentence = match.group(0)?.trim() ?? '';
        if (sentence.isEmpty) {
          continue;
        }
        lines.add(sentence);
        addedSentence = true;
      }

      if (!addedSentence) {
        lines.add(trimmedBlock);
      }
    }

    return lines.isEmpty ? [normalized] : lines;
  }
}
