package injector

type Injector interface {
	Inject(text string) error
	CopyOnly(text string) error
}

var Default Injector
