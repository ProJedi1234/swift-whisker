extension Style {
    func resolved(
        with environment: EnvironmentValues,
        fallbackForeground: Color? = nil,
        fallbackBackground: Color? = nil
    ) -> Style {
        var copy = self

        if copy.foreground == .default {
            if environment.foregroundColor != .default {
                copy.foreground = environment.foregroundColor
            } else if let fallbackForeground {
                copy.foreground = fallbackForeground
            }
        }

        if copy.background == .default {
            if environment.backgroundColor != .default {
                copy.background = environment.backgroundColor
            } else if let fallbackBackground {
                copy.background = fallbackBackground
            }
        }

        if environment.bold {
            copy.attributes.insert(.bold)
        }
        if environment.italic {
            copy.attributes.insert(.italic)
        }
        if environment.underline {
            copy.attributes.insert(.underline)
        }

        return copy
    }
}
