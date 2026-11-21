package cleaner

import (
	"testing"
)

func TestCleanText(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Removes single fillers",
			input:    "Hola este, cómo estás eh? yo estoy bien.",
			expected: "Hola cómo estás? Yo estoy bien.",
		},
		{
			name:     "Removes repeated words (stutter)",
			input:    "yo yo creo que que deberíamos ir a comer.",
			expected: "Yo creo que deberíamos ir a comer.",
		},
		{
			name:     "Removes filler phrases and fixes capitalization",
			input:    "o sea, necesitamos avanzar con el proyecto. bueno pues, nos vemos mañana.",
			expected: "Necesitamos avanzar con el proyecto. Nos vemos mañana.",
		},
		{
			name:     "Voice commands: punto y aparte",
			input:    "Primer párrafo. punto y aparte Segundo párrafo.",
			expected: "Primer párrafo.\n\nSegundo párrafo.",
		},
		{
			name:     "Voice commands: punto 1, punto 2 formatting",
			input:    "Tareas de hoy: punto 1 revisar código. punto dos probar en mac.",
			expected: "Tareas de hoy:\n1.- Revisar código.\n2.- Probar en mac.",
		},
		{
			name:     "Voice commands: bullets and sub-items",
			input:    "Requisitos: viñeta Docker viñeta base de datos inciso a Postgres",
			expected: "Requisitos:\n- Docker\n- Base de datos\na) Postgres",
		},
		{
			name:     "User test with 2 puntos, piñata, robayemail and commas",
			input:    "Reporte de despliegue, 2 puntos. 1. Actualiza el contenedor en Docker con la nueva API SQL,.\n2.- Verificar que el endpoint responde en JSON, piñata, realizar prueba en localhost, piñata. Enviar reporte a su puerta, robayemail.com.",
			expected: "Reporte de despliegue:\n1.- Actualiza el contenedor en Docker con la nueva API SQL.\n2.- Verificar que el endpoint responde en JSON\n- Realizar prueba en localhost\n- Enviar reporte a soporte@gmail.com.",
		},
		{
			name:     "Pineta phonetic and double dots",
			input:    "Reporte de despliegue:\n1.- Actualiza el contenedor en Docker con la nueva API SQL..\n2.- Verificar que el endpoint responde en JSON, piñeta. Realizar prueba en localhost, piñeta. Enviar reporte a soporte@gmail.com.",
			expected: "Reporte de despliegue:\n1.- Actualiza el contenedor en Docker con la nueva API SQL.\n2.- Verificar que el endpoint responde en JSON\n- Realizar prueba en localhost\n- Enviar reporte a soporte@gmail.com.",
		},
		{
			name:     "Blank audio and noise placeholders discarded",
			input:    "[AUDIO_EN_BLANCO]",
			expected: "",
		},
		{
			name:     "Music and silence discarded",
			input:    "[MÚSICA]   ",
			expected: "",
		},
		{
			name:     "Clean input remains clean",
			input:    "El reporte está listo para ser enviado.",
			expected: "El reporte está listo para ser enviado.",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			actual := CleanText(tc.input)
			if actual != tc.expected {
				t.Errorf("\nInput:    %q\nExpected: %q\nActual:   %q", tc.input, tc.expected, actual)
			}
		})
	}
}
