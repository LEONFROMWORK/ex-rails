export default {
  common: {
    app_name: 'ExcelApp',
    loading: '로딩 중...',
    error: '오류',
    success: '성공',
    cancel: '취소',
    save: '저장',
    delete: '삭제',
    edit: '수정',
    reset: '초기화'
  },
  excel: {
    uploader: {
      title: '엑셀 파일 업로드',
      description: '데이터 처리 및 분석을 위해 엑셀 파일을 업로드하세요',
      dragDrop: '파일을 여기에 드래그하세요',
      orClick: '또는 클릭하여 파일 선택',
      selectFile: '파일 선택',
      uploading: '업로드 중...',
      uploadFile: '파일 업로드',
      uploadSuccess: '업로드 완료',
      uploadError: '업로드 실패. 다시 시도해주세요.',
      fileSelected: '선택된 파일',
      removeFile: '파일 제거',
      invalidFileType: '올바른 엑셀 파일(.xlsx, .xls) 또는 CSV 파일을 업로드하세요',
      fileSizeError: '파일 크기는 10MB 이하여야 합니다'
    }
  },
  home: {
    title: 'Vue + shadcn/ui - Rails 통합',
    excelProcessing: '엑셀 처리',
    excelProcessingDesc: '엑셀 파일 업로드 및 처리',
    useVueUploader: 'Vue.js로 스프레드시트를 처리하는 엑셀 업로더를 사용하세요',
    goToUploader: '업로더로 이동'
  },
  payment: {
    widget: {
      title: '결제하기',
      description: '안전한 결제를 진행해주세요',
      loading: '결제 위젯을 불러오는 중...',
      orderName: '주문명',
      totalAmount: '총 결제금액',
      payButton: '{amount} 결제하기',
      processing: '처리중...',
      error: '결제 오류',
      initError: '결제 위젯 초기화에 실패했습니다',
      userCancel: '결제를 취소하셨습니다',
      invalidCard: '올바른 카드 정보를 입력해주세요',
      paymentError: '결제 처리 중 오류가 발생했습니다'
    },
    success: {
      title: '결제가 완료되었습니다',
      description: '정상적으로 결제가 처리되었습니다',
      orderId: '주문번호',
      amount: '결제금액',
      approvedAt: '승인시간',
      goHome: '홈으로',
      viewReceipt: '영수증 보기'
    },
    fail: {
      title: '결제에 실패했습니다',
      description: '결제 처리 중 문제가 발생했습니다',
      errorTitle: '오류 내용',
      goBack: '이전으로',
      retry: '다시 시도',
      canceled: '사용자가 결제를 취소했습니다',
      invalidCard: '카드 정보가 올바르지 않습니다',
      insufficientBalance: '잔액이 부족합니다',
      defaultError: '결제 처리 중 오류가 발생했습니다'
    }
  }
}