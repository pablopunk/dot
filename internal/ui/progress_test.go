package ui

import (
	"testing"
	"time"
)

func TestNewProgressManager(t *testing.T) {
	tests := []struct {
		name  string
		quiet bool
	}{
		{"quiet mode", true},
		{"animated mode", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pm := NewProgressManager(tt.quiet)
			if pm == nil {
				t.Fatal("NewProgressManager() returned nil")
			}

			if pm.quiet != tt.quiet {
				t.Errorf("NewProgressManager() quiet = %v, want %v", pm.quiet, tt.quiet)
			}

			if pm.sections == nil {
				t.Error("NewProgressManager() sections should be initialized")
			}

			if len(pm.sections) != 0 {
				t.Errorf("NewProgressManager() should start with 0 sections, got %d", len(pm.sections))
			}
		})
	}
}

func TestProgressManagerNewSection(t *testing.T) {
	tests := []struct {
		name  string
		quiet bool
		title string
	}{
		{"quiet mode section", true, "Test Section"},
		{"animated mode section", false, "Another Test"},
		{"empty title", false, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pm := NewProgressManager(tt.quiet)
			section := pm.NewSection(tt.title)

			if section == nil {
				t.Fatal("NewSection() returned nil")
			}

			if section.title != tt.title {
				t.Errorf("NewSection() title = %v, want %v", section.title, tt.title)
			}

			if tt.quiet {
				// In quiet mode, spinner should be nil
				if section.spinner != nil {
					t.Error("NewSection() in quiet mode should have nil spinner")
				}
			} else {
				// In animated mode, spinner should be initialized
				if section.spinner == nil {
					t.Error("NewSection() in animated mode should have non-nil spinner")
				}
			}

			// Check that section was added to manager
			if len(pm.sections) != 1 {
				t.Errorf("NewSection() should add section to manager, got %d sections", len(pm.sections))
			}

			if pm.sections[0] != section {
				t.Error("NewSection() should add the created section to manager")
			}
		})
	}
}

func TestProgressSectionQuietMode(t *testing.T) {
	pm := NewProgressManager(true) // quiet mode
	section := pm.NewSection("Test")

	// These should not panic in quiet mode
	section.Start()
	section.Update("Updated message")
	section.Complete("Completed")

	// Create another section for other completion types
	section2 := pm.NewSection("Test 2")
	section2.Start()
	section2.Fail("Failed")

	section3 := pm.NewSection("Test 3")
	section3.Start()
	section3.Skip("Skipped")

	// StopAll should not panic
	pm.StopAll()
}

func TestProgressSectionAnimatedMode(t *testing.T) {
	pm := NewProgressManager(false) // animated mode
	section := pm.NewSection("Test")

	if section.spinner == nil {
		t.Fatal("Spinner should be initialized in animated mode")
	}

	// Test lifecycle - these should not panic
	section.Start()
	
	// Small delay to let spinner start
	time.Sleep(10 * time.Millisecond)
	
	section.Update("Updated message")
	time.Sleep(10 * time.Millisecond)
	
	section.Complete("Completed")

	// Test failure case
	section2 := pm.NewSection("Test 2")
	section2.Start()
	time.Sleep(10 * time.Millisecond)
	section2.Fail("Failed")
	_ = section2

	// Test skip case
	section3 := pm.NewSection("Test 3")
	section3.Start()
	time.Sleep(10 * time.Millisecond)
	section3.Skip("Skipped")

	// StopAll should not panic
	pm.StopAll()
}

func TestNewComponentProgress(t *testing.T) {
	pm := NewProgressManager(false)
	componentName := "test-component"
	
	cp := pm.NewComponentProgress(componentName)
	if cp == nil {
		t.Fatal("NewComponentProgress() returned nil")
	}

	if cp.component != componentName {
		t.Errorf("NewComponentProgress() component = %v, want %v", cp.component, componentName)
	}

	if cp.section == nil {
		t.Error("NewComponentProgress() section should not be nil")
	}

	// Check that section was created with correct title
	expectedTitle := "Processing test-component..."
	if cp.section.title != expectedTitle {
		t.Errorf("NewComponentProgress() section title = %v, want %v", cp.section.title, expectedTitle)
	}
}

func TestComponentProgressLifecycle(t *testing.T) {
	tests := []struct {
		name  string
		quiet bool
	}{
		{"quiet mode", true},
		{"animated mode", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pm := NewProgressManager(tt.quiet)
			cp := pm.NewComponentProgress("test-component")

			// Test complete lifecycle - these should not panic
			cp.StartInstalling()
			
			if !tt.quiet {
				time.Sleep(10 * time.Millisecond)
			}
			
			cp.StartLinking()
			
			if !tt.quiet {
				time.Sleep(10 * time.Millisecond)
			}
			
			cp.StartPostHooks()
			
			if !tt.quiet {
				time.Sleep(10 * time.Millisecond)
			}
			
			cp.CompleteSuccess()

			// Test failure case
			cp2 := pm.NewComponentProgress("test-component-2")
			cp2.StartInstalling()
			
			if !tt.quiet {
				time.Sleep(10 * time.Millisecond)
			}
			
			cp2.CompleteFailed(testError{})

			// Test skip case
			cp3 := pm.NewComponentProgress("test-component-3")
			cp3.CompleteSkipped()

			pm.StopAll()
		})
	}
}

func TestComponentProgressPhases(t *testing.T) {
	pm := NewProgressManager(false) // Use animated mode to test spinner updates
	cp := pm.NewComponentProgress("test-component")

	// Start and check each phase updates the spinner message correctly
	// We can't easily test the actual spinner message without accessing internals,
	// but we can at least ensure the methods don't panic and run successfully

	cp.StartInstalling()
	time.Sleep(10 * time.Millisecond)

	cp.StartLinking() 
	time.Sleep(10 * time.Millisecond)

	cp.StartPostHooks()
	time.Sleep(10 * time.Millisecond)

	cp.CompleteSuccess()
}

func TestMultipleSections(t *testing.T) {
	pm := NewProgressManager(false)

	// Create multiple sections
	section1 := pm.NewSection("Section 1")
	section2 := pm.NewSection("Section 2") 
	section3 := pm.NewSection("Section 3")

	if len(pm.sections) != 3 {
		t.Errorf("Expected 3 sections, got %d", len(pm.sections))
	}

	// Start them all
	section1.Start()
	section2.Start()
	section3.Start()

	time.Sleep(10 * time.Millisecond)

	// Complete them in different ways
	section1.Complete("Done 1")
	section2.Fail("Failed 2")
	section3.Skip("Skipped 3")

	// StopAll should handle any remaining active sections
	pm.StopAll()
}

func TestStopAllWithActiveSections(t *testing.T) {
	pm := NewProgressManager(false)

	// Create sections and start some
	section1 := pm.NewSection("Active 1")
	section2 := pm.NewSection("Not Started")
	section3 := pm.NewSection("Active 2")

	section1.Start()
	section3.Start()
	// section2 never started

	time.Sleep(10 * time.Millisecond)

	// StopAll should only affect active sections
	pm.StopAll()

	// This should not panic - calling StopAll again
	pm.StopAll()
}

func TestProgressManagerDefer(t *testing.T) {
	// Test the common usage pattern with defer
	func() {
		pm := NewProgressManager(false)
		defer pm.StopAll()

		section := pm.NewSection("Test")
		section.Start()
		time.Sleep(10 * time.Millisecond)
		// section not explicitly completed - defer should handle it
	}()

	// If we get here without panic, the defer worked correctly
}

// Test error type for testing
type testError struct{}

func (e testError) Error() string {
	return "test error"
}

func TestComponentProgressErrors(t *testing.T) {
	pm := NewProgressManager(true) // quiet mode for predictable testing
	cp := pm.NewComponentProgress("test-component")

	// Test with different error types
	errors := []error{
		testError{},
		&testError{},
		nil, // This might cause issues, but shouldn't panic
	}

	for i, err := range errors {
		cp := pm.NewComponentProgress("test-component")
		cp.StartInstalling()
		cp.CompleteFailed(err) // Should not panic regardless of error type
		
		// Verify component name is preserved
		if cp.component != "test-component" {
			t.Errorf("Test %d: component name changed", i)
		}
	}
}

func TestSectionActiveFlag(t *testing.T) {
	pm := NewProgressManager(false)
	section := pm.NewSection("Test")

	// Initially should not be active
	if section.active {
		t.Error("New section should not be active")
	}

	// Start should set active to true
	section.Start()
	if !section.active {
		t.Error("Started section should be active")
	}

	time.Sleep(10 * time.Millisecond)

	// Complete should set active to false
	section.Complete("Done")
	if section.active {
		t.Error("Completed section should not be active")
	}
}

func TestEdgeCaseInputs(t *testing.T) {
	pm := NewProgressManager(false)

	// Test with empty strings
	section := pm.NewSection("")
	section.Start()
	section.Update("")
	section.Complete("")

	// Test with very long strings
	longString := make([]byte, 1000)
	for i := range longString {
		longString[i] = 'a'
	}
	longStr := string(longString)

	section2 := pm.NewSection(longStr)
	section2.Start()
	section2.Update(longStr)
	section2.Complete(longStr)
	
	_ = section2 // Mark as used

	pm.StopAll()
}