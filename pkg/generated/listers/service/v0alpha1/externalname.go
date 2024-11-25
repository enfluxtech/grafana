// SPDX-License-Identifier: AGPL-3.0-only

// Code generated by lister-gen. DO NOT EDIT.

package v0alpha1

import (
	v0alpha1 "github.com/grafana/grafana/pkg/apis/service/v0alpha1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/listers"
	"k8s.io/client-go/tools/cache"
)

// ExternalNameLister helps list ExternalNames.
// All objects returned here must be treated as read-only.
type ExternalNameLister interface {
	// List lists all ExternalNames in the indexer.
	// Objects returned here must be treated as read-only.
	List(selector labels.Selector) (ret []*v0alpha1.ExternalName, err error)
	// ExternalNames returns an object that can list and get ExternalNames.
	ExternalNames(namespace string) ExternalNameNamespaceLister
	ExternalNameListerExpansion
}

// externalNameLister implements the ExternalNameLister interface.
type externalNameLister struct {
	listers.ResourceIndexer[*v0alpha1.ExternalName]
}

// NewExternalNameLister returns a new ExternalNameLister.
func NewExternalNameLister(indexer cache.Indexer) ExternalNameLister {
	return &externalNameLister{listers.New[*v0alpha1.ExternalName](indexer, v0alpha1.Resource("externalname"))}
}

// ExternalNames returns an object that can list and get ExternalNames.
func (s *externalNameLister) ExternalNames(namespace string) ExternalNameNamespaceLister {
	return externalNameNamespaceLister{listers.NewNamespaced[*v0alpha1.ExternalName](s.ResourceIndexer, namespace)}
}

// ExternalNameNamespaceLister helps list and get ExternalNames.
// All objects returned here must be treated as read-only.
type ExternalNameNamespaceLister interface {
	// List lists all ExternalNames in the indexer for a given namespace.
	// Objects returned here must be treated as read-only.
	List(selector labels.Selector) (ret []*v0alpha1.ExternalName, err error)
	// Get retrieves the ExternalName from the indexer for a given namespace and name.
	// Objects returned here must be treated as read-only.
	Get(name string) (*v0alpha1.ExternalName, error)
	ExternalNameNamespaceListerExpansion
}

// externalNameNamespaceLister implements the ExternalNameNamespaceLister
// interface.
type externalNameNamespaceLister struct {
	listers.ResourceIndexer[*v0alpha1.ExternalName]
}