package injector

import (
	"testing"
)

func TestInjectorInterface(t *testing.T) {
	if Default == nil {
		t.Fatal("Expected Default injector to be initialized")
	}

	// Test Empty text does not fail
	err := Default.Inject("")
	if err != nil {
		t.Errorf("Inject with empty text should return nil, got: %v", err)
	}
}
