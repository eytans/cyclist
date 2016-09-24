#ifndef FAIR_PROOF_AUTOMATON_HH_
#define FAIR_PROOF_AUTOMATON_HH_

#include <spot/twa/twa.hh>

#include "proof.hpp"

//==================================================================
class ProofState: public spot::state {
public:
  const Vertex vertex;
  const TagVector & tags;
  
  ProofState(const Vertex & v, const TagVector & ts) : vertex(v), tags(ts) {}
  
  virtual int compare(const spot::state* other) const;
  virtual size_t hash() const { return vertex.id(); }
  virtual spot::state* clone() const { return new ProofState(vertex, tags); }
};
//==================================================================
class ProofGhostState: public spot::state {
public:
  virtual int compare(const spot::state* other) const;
  virtual size_t hash() const { return 0; }
  virtual spot::state* clone() const { return new ProofGhostState(); }
};
//==================================================================
class FairProofAutomaton: public spot::twa, public Proof {
public:
  FairProofAutomaton(size_t max_vertices_log2) : Proof(max_vertices_log2), spot::twa(spot::make_bdd_dict()) { set_generalized_buchi(2); // TODO: This most likely will have to change to a more complex acceptance condition
    this->dict_ = Proof::get_dict(); register_aps_from_dict(); }
  
  virtual ~FairProofAutomaton() {};
  virtual spot::state* get_init_state() const { return new ProofGhostState(); }
  virtual spot::bdd_dict_ptr get_dict() const { return Proof::get_dict(); }
  virtual spot::twa_succ_iterator* succ_iter(const spot::state* local_state) const;
  virtual std::string format_state(const spot::state* state) const;
  //	virtual std::string transition_annotation(const spot::tgba_succ_iterator* t) const;
  //	virtual spot::state* project_state(const spot::state* s, const spot::tgba* t) const;
};
//==================================================================
class ProofGhostSuccIterator: public spot::twa_succ_iterator {
private:
  const ProofAutomaton & proof;
  bool finished;

public:
  ProofGhostSuccIterator(const ProofAutomaton & p) : proof(p), finished(false) {}

  virtual bool first() { finished = false; return !done(); }
  virtual bool next() { finished = true; return !done(); }
  virtual bool done() const { return finished; }
  virtual spot::state* dst() const {
    Vertex v = proof.get_initial_vertex();
    return new ProofState(v, proof.get_tags_of_vertex(v) );
  }
  virtual bdd cond() const { return proof.get_initial_vertex(); }
  virtual spot::acc_cond::mark_t acc() const { return proof.acc().all_sets(); }
};
//==================================================================
class ProofSuccIterator: public spot::twa_succ_iterator {
private:
  const ProofAutomaton & proof;
  Vertex vertex;
  VertexSet::const_iterator successor;

public:
  ProofSuccIterator(const ProofAutomaton & p, const Vertex & v) : proof(p), vertex(v) {}

  virtual bool first() { successor = proof.get_successors(vertex).begin(); return !done(); }
  virtual bool next() { ++successor; return !done(); }
  virtual bool done() const { return successor == proof.get_successors(vertex).end(); }
  virtual spot::state* dst() const {
    return new ProofState(*successor, proof.get_tags_of_vertex(*successor) );
  }
  virtual bdd cond() const { return *successor; } //TODO: write correct implementation
  virtual spot::acc_cond::mark_t acc() const { return proof.acc().all_sets(); // TODO: write correct implementation
  }
};
//==================================================================
#endif /* PROOF_AUTOMATON_HH_ */