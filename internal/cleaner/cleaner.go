package cleaner

import (
	"fmt"
	"regexp"
	"strings"
	"unicode"
)

var (
	// Multi-word filler phrases to remove
	fillerPhrases = []string{
		"bueno pues",
		"o sea",
		"es decir",
		"digo yo",
		"la verdad es que",
		"como te digo",
		"digamos que",
		"por así decirlo",
		"por decirlo así",
		"en plan",
	}

	// Single filler words in Spanish and English
	fillerWords = []string{
		"este",
		"eh",
		"em",
		"um",
		"uh",
		"ah",
		"ajá",
		"mmm",
	}

	// Punctuation cleanups
	spaceBeforePunctuation = regexp.MustCompile(`[ \t]+([,.;:?!])`)
	multipleSpaces         = regexp.MustCompile(`[ \t]{2,}`)
	multipleNewlines       = regexp.MustCompile(`\n{3,}`)
	isolatedPunctuation    = regexp.MustCompile(`^[,.;:?!]\s*`)
	sentenceEndRegex       = regexp.MustCompile(`([.!?]\s+|\n{2,}|(?:^|\n)\d+\.-\s+|(?:^|\n)[a-zA-Z]\)\s+|(?:^|\n)-\s+)([a-záéíóúñ])`)

	// Double punctuation cleanups like ",." or ".,"
	mixedPunctuation1 = regexp.MustCompile(`[,;]+([.])`)
	mixedPunctuation2 = regexp.MustCompile(`([.])[,;]+`)
	multipleCommas    = regexp.MustCompile(`[,]{2,}`)

	// Whisper sound artifacts / placeholders
	whisperArtifacts = regexp.MustCompile(`(?i)\[(?:audio_en_blanco|audio\s+en\s+blanco|blank_audio|música|musica|silencio|silence|ruido|aplausos|risas|tos)\]|\((?:silencio|música|musica)\)`)

	// Voice command replacements (symbols, punctuation, structural formatting)
	dictationCommands = []struct {
		regex *regexp.Regexp
		repl  string
	}{
		// Paragraphs and lines
		{regexp.MustCompile(`(?i)\s*\b(?:punto\s+(?:y\s+|de\s+)?aparte|nuevo\s+párrafo|salto\s+de\s+línea)\b[,.]?\s*`), ".\n\n"},
		{regexp.MustCompile(`(?i)\b(?:nueva\s+línea)\b[,.]?\s*`), "\n"},
		{regexp.MustCompile(`(?i)\b(?:punto\s+y\s+seguido)\b[,.]?\s*`), ". "},

		// Punctuation marks (including "2 puntos" / "dos puntos")
		{regexp.MustCompile(`(?i)(?:,\s*)?\b(?:dos|2)\s+puntos\b[:.]?\s*`), ": "},
		{regexp.MustCompile(`(?i)\b(?:punto\s+y\s+coma)\b[,.]?\s*`), "; "},
		{regexp.MustCompile(`(?i)\b(?:coma)\b\s*`), ", "},
		{regexp.MustCompile(`(?i)\s*\b(?:cierra\s+interrogación|signo\s+de\s+interrogación)\b[,.]?\s*`), "? "},
		{regexp.MustCompile(`(?i)\b(?:abre\s+interrogación)\b\s*`), " ¿"},
		{regexp.MustCompile(`(?i)\s*\b(?:cierra\s+exclamación|cierra\s+admiración|signo\s+de\s+exclamación|signo\s+de\s+admiración)\b[,.]?\s*`), "! "},
		{regexp.MustCompile(`(?i)\b(?:abre\s+exclamación|abre\s+admiración)\b\s*`), " ¡"},

		// Parentheses and quotes
		{regexp.MustCompile(`(?i)\b(?:abrir\s+paréntesis|abre\s+paréntesis)\b\s*`), " ("},
		{regexp.MustCompile(`(?i)\s*\b(?:cerrar\s+paréntesis|cierra\s+paréntesis)\b\s*`), ") "},
		{regexp.MustCompile(`(?i)\b(?:abrir\s+comillas|abre\s+comillas)\b\s*`), ` "`},
		{regexp.MustCompile(`(?i)\s*\b(?:cerrar\s+comillas|cierra\s+comillas)\b\s*`), `" `},

		// Internet & Tech symbols
		{regexp.MustCompile(`(?i)\b(?:su\s+puerta|su\s+puerto|su\s+aporte)\s*[,.]?\s*`), "soporte "},
		{regexp.MustCompile(`(?i)\s*\b(?:arroba|roba)\s*(?:y\s*email|yei\s*mail|ymail|gmail|email|mail)\.com\b`), "@gmail.com"},
		{regexp.MustCompile(`(?i)\s*\b(?:arroba|roba)\b\s*`), "@"},
		{regexp.MustCompile(`(?i)\s*\b(?:hashtag|almohadilla|numeral)\b\s*`), " #"},
		{regexp.MustCompile(`(?i)\s*\b(?:por\s*ciento|porcentaje)\b\s*`), "%"},
		{regexp.MustCompile(`(?i)\s*\b(?:guión\s+bajo|underscore)\b\s*`), "_"},
		{regexp.MustCompile(`(?i)\s*\b(?:barra\s+diagonal|slash)\b\s*`), "/"},
		{regexp.MustCompile(`(?i)\s*\b(?:punto\s+com)\b`), ".com"},
		{regexp.MustCompile(`(?i)\b(?:triple\s+doble\s+ve\s+punto|doble\s+ve\s+doble\s+ve\s+doble\s+ve\s+punto)\s*`), "www."},
	}

	// Developer / Tech terms autocorrect
	techTerms = []struct {
		regex *regexp.Regexp
		repl  string
	}{
		{regexp.MustCompile(`(?i)\b(?:yason|jason|jeison)\b`), "JSON"},
		{regexp.MustCompile(`(?i)\b(?:a\s+pi|ei\s+pi\s+ai)\b`), "API"},
		{regexp.MustCompile(`(?i)\b(?:secuela|secula|ese\s+cu\s+ele|ese\s+qu\s+ele|seql)\b`), "SQL"},
		{regexp.MustCompile(`(?i)\b(?:pull\s+riquest)\b`), "pull request"},
		{regexp.MustCompile(`(?i)\b(?:git\s+comit)\b`), "git commit"},
		{regexp.MustCompile(`(?i)\b(?:taipscrip|type\s+script)\b`), "TypeScript"},
		{regexp.MustCompile(`(?i)\b(?:yavascrip|java\s+script)\b`), "JavaScript"},
		{regexp.MustCompile(`(?i)\b(?:local[.\s]+host)\b`), "localhost"},
		{regexp.MustCompile(`(?i)\b(?:git\s+hub)\b`), "GitHub"},
		{regexp.MustCompile(`(?i)\b(?:en\s*point|n\s*point|npn)\b`), "endpoint"},
		{regexp.MustCompile(`(?i)\b(?:display\s+de)\b`), "despliegue de"},
		{regexp.MustCompile(`(?i)@ymail\.com\b`), "@gmail.com"},
	}

	// Number words in Spanish mapped to digits
	numberWords = map[string]int{
		"uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
		"seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
		"once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
		"dieciséis": 16, "diecisiete": 17, "dieciocho": 18, "diecinueve": 19, "veinte": 20,
	}

	// List patterns like "punto 1", "punto uno", "número 1" or standalone "1. "
	numberedListRegex = regexp.MustCompile(`(?i)(?:^|\n|[.!?:]\s*)\b(?:(?:punto|número)\s+(\d+|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|trece|catorce|quince|dieciséis|diecisiete|dieciocho|diecinueve|veinte)|(\d+)\.(?:\s+|$))`)

	// Sub-item list patterns: "inciso a", "inciso b", etc.
	letteredListRegex = regexp.MustCompile(`(?i)(?:^|\n|[,.!?:]?\s*)\binciso\s+([a-e])\b[:\.\-]?\s*`)

	// Bullet point list patterns: "viñeta", "piñeta", "piñata", "bullet", "guión"
	bulletListRegex = regexp.MustCompile(`(?i)(?:^|\n|[,.!?:]?\s*)\b(?:viñeta|biñeta|piñeta|vineta|pineta|piñata|bullet|guión|guion)\b[:\.\-]?\s*`)
)

// CleanText applies rules to remove filler words, stutters, and format punctuation/lists nicely.
func CleanText(input string) string {
	text := strings.TrimSpace(input)
	if text == "" {
		return ""
	}

	// 0. Strip whisper audio artifacts and silence placeholders
	text = whisperArtifacts.ReplaceAllString(text, "")
	text = strings.TrimSpace(text)
	if text == "" || !hasAlphanumeric(text) {
		return ""
	}

	// 1. Process voice commands ("punto y aparte", "dos puntos", símbolos)
	for _, cmd := range dictationCommands {
		text = cmd.regex.ReplaceAllString(text, cmd.repl)
	}

	// 2. Format numbered list items: "punto 1", "punto uno", or "1." -> "\n1.- "
	text = numberedListRegex.ReplaceAllStringFunc(text, func(m string) string {
		prefix := ""
		if strings.HasPrefix(m, ":") {
			prefix = ":"
		} else if strings.HasPrefix(m, ".") {
			prefix = "."
		}
		submatches := numberedListRegex.FindStringSubmatch(m)
		if len(submatches) >= 2 {
			valStr := strings.ToLower(submatches[1])
			if valStr == "" && len(submatches) >= 3 {
				valStr = strings.ToLower(submatches[2])
			}
			num := 0
			if n, ok := numberWords[valStr]; ok {
				num = n
			} else {
				_, _ = fmt.Sscanf(valStr, "%d", &num)
			}
			if num > 0 {
				return fmt.Sprintf("%s\n%d.- ", prefix, num)
			}
		}
		return m
	})

	// 3. Format lettered sub-items: "inciso a" -> "\na) "
	text = letteredListRegex.ReplaceAllStringFunc(text, func(m string) string {
		prefix := ""
		if strings.HasPrefix(m, ":") {
			prefix = ":"
		} else if strings.HasPrefix(m, ".") {
			prefix = "."
		}
		submatches := letteredListRegex.FindStringSubmatch(m)
		if len(submatches) >= 2 {
			return fmt.Sprintf("%s\n%s) ", prefix, strings.ToLower(submatches[1]))
		}
		return m
	})

	// 4. Format bullet points: "viñeta" / "piñata" -> "\n- "
	text = bulletListRegex.ReplaceAllStringFunc(text, func(m string) string {
		prefix := ""
		if strings.HasPrefix(m, ":") {
			prefix = ":"
		} else if strings.HasPrefix(m, ".") {
			prefix = "."
		}
		return fmt.Sprintf("%s\n- ", prefix)
	})

	// 5. Tech terms autocorrection
	for _, term := range techTerms {
		text = term.regex.ReplaceAllString(text, term.repl)
	}

	// Fix duplicate dots ".. " that might have occurred from ".\n\n"
	text = strings.ReplaceAll(text, "..\n\n", ".\n\n")

	// 6. Remove multi-word filler phrases
	for _, phrase := range fillerPhrases {
		pattern := `(?i)\b` + regexp.QuoteMeta(phrase) + `\b,?\s*`
		re := regexp.MustCompile(pattern)
		text = re.ReplaceAllString(text, "")
	}

	// 7. Remove single filler words
	for _, word := range fillerWords {
		pattern := `(?i)\b` + regexp.QuoteMeta(word) + `\b,?\s*`
		re := regexp.MustCompile(pattern)
		text = re.ReplaceAllString(text, "")
	}

	// 8. Remove consecutive duplicate words line by line
	text = removeDuplicateWords(text)

	// 9. Fix spaces around punctuation and double punctuation
	text = spaceBeforePunctuation.ReplaceAllString(text, "$1")
	text = mixedPunctuation1.ReplaceAllString(text, "$1")
	text = mixedPunctuation2.ReplaceAllString(text, "$1")
	text = multipleCommas.ReplaceAllString(text, ",")
	text = regexp.MustCompile(`\.{2}`).ReplaceAllString(text, ".")
	text = multipleSpaces.ReplaceAllString(text, " ")
	text = multipleNewlines.ReplaceAllString(text, "\n\n")
	text = isolatedPunctuation.ReplaceAllString(text, "")

	// Strip commas/periods mistakenly attached to list markers (e.g. "1.-," -> "1.-", "-," -> "-")
	listMarkerCommaRegex := regexp.MustCompile(`((?:^|\n)\s*(?:\d+\.-|-|[a-zA-Z]\)))\s*[,.]\s*`)
	text = listMarkerCommaRegex.ReplaceAllString(text, "$1 ")

	// Strip double dashes or trailing dashes on numbered lists (e.g. "2.- -" -> "2.- ")
	text = regexp.MustCompile(`(\d+\.-)\s*-\s*`).ReplaceAllString(text, "$1 ")
	// Strip comma at end of line before newline
	text = regexp.MustCompile(`,\s*\n`).ReplaceAllString(text, "\n")

	// 10. Trim leading/trailing whitespace
	text = strings.TrimSpace(text)
	if text == "" || !hasAlphanumeric(text) {
		return ""
	}

	// 11. Ensure first letter is capitalized
	runes := []rune(text)
	runes[0] = unicode.ToUpper(runes[0])
	text = string(runes)

	// 12. Capitalize letters after sentence-ending punctuation, newlines, or list items
	text = sentenceEndRegex.ReplaceAllStringFunc(text, func(m string) string {
		parts := sentenceEndRegex.FindStringSubmatch(m)
		if len(parts) == 3 {
			return parts[1] + strings.ToUpper(parts[2])
		}
		return m
	})

	text = strings.TrimSpace(text)
	if !hasAlphanumeric(text) {
		return ""
	}
	return text
}

// removeDuplicateWords removes immediate duplicate words line by line to preserve newlines.
func removeDuplicateWords(text string) string {
	lines := strings.Split(text, "\n")
	for idx, line := range lines {
		words := strings.Fields(line)
		if len(words) <= 1 {
			continue
		}
		var result []string
		var lastCleanWord string
		for _, w := range words {
			clean := strings.ToLower(strings.Trim(w, ",.;:?!"))
			if clean != "" && clean == lastCleanWord {
				continue
			}
			result = append(result, w)
			if clean != "" {
				lastCleanWord = clean
			}
		}
		lines[idx] = strings.Join(result, " ")
	}
	return strings.Join(lines, "\n")
}

func hasAlphanumeric(s string) bool {
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return true
		}
	}
	return false
}
