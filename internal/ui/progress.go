package ui

import (
	"fmt"
	"time"

	"github.com/briandowns/spinner"
)

// ProgressSection represents a single animated section that can be started, updated, and completed
type ProgressSection struct {
	spinner *spinner.Spinner
	title   string
	active  bool
	paused  bool
}

// ProgressManager manages multiple progress sections
type ProgressManager struct {
	sections []*ProgressSection
	quiet    bool
}

// NewProgressManager creates a new progress manager
func NewProgressManager(quiet bool) *ProgressManager {
	return &ProgressManager{
		sections: make([]*ProgressSection, 0),
		quiet:    quiet,
	}
}

// NewSection creates a new progress section with a spinner
func (pm *ProgressManager) NewSection(title string) *ProgressSection {
	if pm.quiet {
		return &ProgressSection{title: title}
	}

	s := spinner.New(spinner.CharSets[14], 100*time.Millisecond)
	s.Suffix = fmt.Sprintf(" %s", title)
	s.FinalMSG = fmt.Sprintf("%s\n", Success(title))

	section := &ProgressSection{
		spinner: s,
		title:   title,
		active:  false,
	}

	pm.sections = append(pm.sections, section)
	return section
}

// Start begins the animation for this section
func (ps *ProgressSection) Start() {
	if ps.spinner == nil {
		return
	}
	ps.active = true
	ps.spinner.Start()
}

// Update changes the message while keeping the spinner active
func (ps *ProgressSection) Update(message string) {
	if ps.spinner == nil {
		return
	}
	ps.spinner.Suffix = fmt.Sprintf(" %s", message)
}

// Complete stops the spinner and shows a success message
func (ps *ProgressSection) Complete(message string) {
	if ps.spinner == nil {
		return
	}
	ps.active = false
	ps.spinner.FinalMSG = "" // Don't print individual success messages
	ps.spinner.Stop()
}

// Fail stops the spinner and shows a failure message
func (ps *ProgressSection) Fail(message string) {
	if ps.spinner == nil {
		return
	}
	ps.active = false
	ps.spinner.FinalMSG = fmt.Sprintf("%s\n", Error(message)) // Still show errors
	ps.spinner.Stop()
}

// Skip stops the spinner and shows a skip message
func (ps *ProgressSection) Skip(message string) {
	if ps.spinner == nil {
		return
	}
	ps.active = false
	ps.spinner.FinalMSG = "" // Don't print individual skip messages
	ps.spinner.Stop()
}

// StopAll stops all active sections
func (pm *ProgressManager) StopAll() {
	for _, section := range pm.sections {
		if section.active && section.spinner != nil {
			section.spinner.Stop()
			section.active = false
		}
	}
}

// ComponentProgress creates a specialized progress section for component installation
type ComponentProgress struct {
	section   *ProgressSection
	component string
}

// NewComponentProgress creates a progress section specifically for component operations
func (pm *ProgressManager) NewComponentProgress(componentName string) *ComponentProgress {
	section := pm.NewSection(fmt.Sprintf("Processing %s...", componentName))
	return &ComponentProgress{
		section:   section,
		component: componentName,
	}
}

// StartInstalling starts the installation phase
func (cp *ComponentProgress) StartInstalling() {
	cp.section.Start()
	cp.section.Update(fmt.Sprintf("Installing %s...", cp.component))
}

// StartLinking updates to linking phase
func (cp *ComponentProgress) StartLinking() {
	cp.section.Update(fmt.Sprintf("Linking %s...", cp.component))
}

// StartPostHooks updates to post-hook phase
func (cp *ComponentProgress) StartPostHooks() {
	cp.section.Update(fmt.Sprintf("Running post-hooks for %s...", cp.component))
}

// CompleteSuccess marks the component as successfully completed
func (cp *ComponentProgress) CompleteSuccess() {
	cp.section.Complete(fmt.Sprintf("%s", cp.component))
}

// CompleteFailed marks the component as failed
func (cp *ComponentProgress) CompleteFailed(err error) {
	cp.section.Fail(fmt.Sprintf("%s: %v", cp.component, err))
}

// CompleteSkipped marks the component as skipped
func (cp *ComponentProgress) CompleteSkipped() {
	cp.section.Skip(fmt.Sprintf("%s (skipped)", cp.component))
}

// PauseForInteraction temporarily pauses the spinner for interactive commands
func (ps *ProgressSection) PauseForInteraction(message string) {
	if ps.spinner == nil || !ps.active {
		return
	}
	ps.paused = true
	ps.spinner.Stop()
	// Print the message to indicate what's happening
	fmt.Printf("%s\n", Processing(message))
}

// ResumeAfterInteraction resumes the spinner after interactive command
func (ps *ProgressSection) ResumeAfterInteraction(message string) {
	if ps.spinner == nil || !ps.paused {
		return
	}
	ps.paused = false
	ps.spinner.Suffix = fmt.Sprintf(" %s", message)
	ps.spinner.Start()
}

// PauseForInteraction pauses spinner for interactive commands
func (cp *ComponentProgress) PauseForInteraction(message string) {
	cp.section.PauseForInteraction(fmt.Sprintf("%s: %s", cp.component, message))
}

// ResumeAfterInteraction resumes spinner after interactive commands  
func (cp *ComponentProgress) ResumeAfterInteraction() {
	cp.section.ResumeAfterInteraction(fmt.Sprintf("Completing %s...", cp.component))
}