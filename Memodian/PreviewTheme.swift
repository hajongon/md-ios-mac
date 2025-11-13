//
//  PreviewTheme.swift
//  Memodian
//
//  Created by hajongon on 11/11/25.
//

import SwiftUI
import MarkdownUI

/// currentScale(예: 1.0, 0.9, 0.8 …) + 시스템 테마에 따라 변하는 테마
func previewTheme(scale: CGFloat, colorScheme: ColorScheme) -> Theme {
  // 다크/라이트에 따라 코드블럭 배경 색 분기
  let codeBackground: Color = (colorScheme == .dark)
    ? Color(white: 0.18)
    : Color(white: 0.95)

  return Theme.gitHub
    // 본문 전체 스케일
    .text {
      FontSize(.em(scale))
    }

    // 문단 스케일
    .paragraph { configuration in
      configuration.label
        .markdownTextStyle {
          FontSize(.em(scale))
        }
    }

    // 인라인 코드
    .code {
      FontFamilyVariant(.monospaced)
      FontSize(.em(0.9 * scale))
    }

    // 코드블록: 배경은 화면폭 고정 + 라이트/다크 배경 변경
    .codeBlock { configuration in
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
          .fill(codeBackground)
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .markdownMargin(top: .em(0.75), bottom: .em(0.75))
    }

    // 헤딩들 스케일
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

    // 테이블도 스케일 + 가로 스크롤 (중복 .table 정리)
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
