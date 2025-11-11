//
//  PreviewTheme.swift
//  Memodian
//
//  Created by hajongon on 11/11/25.
//

import SwiftUI
import MarkdownUI

/// currentScale(예: 1.0, 0.9, 0.8 …)에 맞춰 '텍스트만' 스케일하는 테마
func previewTheme(scale: CGFloat) -> Theme {
  Theme.gitHub
    // 본문 전체 스케일
    .text {
      // 기본 대비 배수로 설정 (em 단위)
      FontSize(.em(scale))
    }
    
    // ✅ 문단(Paragraph)에도 직접 적용: 기본 본문 텍스트 스케일 확실히 반영
    .paragraph { configuration in
      configuration.label
        .markdownTextStyle {
          FontSize(.em(scale))
        }
    }
    
    
    // 인라인 코드: 모노스페이스 + 약간 더 작게
    .code {
      FontFamilyVariant(.monospaced)
      FontSize(.em(0.9 * scale))
    }
    // 코드블록: 배경은 화면폭 고정, 내부 글자만 축소/확대
    .codeBlock { configuration in
      // 수평 스크롤 허용 (긴 라인 대응)
      ScrollView(.horizontal) {
        configuration.label
          .markdownTextStyle {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.80 * scale))
          }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(white: 0.95))
      )
      .frame(maxWidth: .infinity, alignment: .leading) // 배경 가로폭 고정
      .markdownMargin(top: .em(0.75), bottom: .em(0.75))
    }
    // 헤딩들도 축소/확대
    .heading1 { configuration in
      configuration.label
        .markdownTextStyle {
          FontSize(.em(1.65 * scale))
          FontWeight(.bold)
        }
    }
    .heading2 { configuration in
      configuration.label
        .markdownTextStyle {
          FontSize(.em(1.35 * scale))
          FontWeight(.semibold)
        }
    }
    .heading3 { configuration in
      configuration.label
        .markdownTextStyle {
          FontSize(.em(1.20 * scale))
          FontWeight(.semibold)
        }
    }

    // 테이블 전체에 스케일 적용 + 가로 스크롤 허용
    .table { configuration in
      ScrollView(.horizontal) {
        configuration.label
          .markdownTextStyle {
            FontSize(.em(scale))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .markdownMargin(top: .em(0.75), bottom: .em(0.75))
    }


    .table { configuration in
      ScrollView(.horizontal) {
        configuration.label
          .markdownTextStyle {
            FontSize(.em(scale))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, 8)
      .markdownMargin(top: .em(0.75), bottom: .em(0.75))
    }


}
