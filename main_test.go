package main

import "testing"

func Test_add(t *testing.T) {
	type args struct {
		a int
		b int
	}
	tests := []struct {
		name string
		args args
		want int
	}{
		{
			name: "one",
			args: args{
				a: 1,
				b: 2,
			},
			want: 3,
		},
		{
			name: "twoo",
			args: args{
				a: 2,
				b: 2,
			},
			want: 4,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := add(tt.args.a, tt.args.b); got != tt.want {
				t.Errorf("add() = %v, want %v", got, tt.want)
			}
		})
	}
}

func Test_additionalTestGoesHere(t *testing.T) {
	t.Run("something", func(t *testing.T) {
		if got := add(1, 2); got != 4 {
			t.Errorf("add() = %v, want %v", got, 3)
		}
	})
}
