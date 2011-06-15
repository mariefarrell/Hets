package  de.unibremen.informatik.atermRenderer;

import org.semanticweb.owlapi.io.AbstractOWLRenderer;
import org.semanticweb.owlapi.io.OWLRendererException;
import org.semanticweb.owlapi.io.OWLRendererIOException;
import org.semanticweb.owlapi.model.OWLException;
import org.semanticweb.owlapi.model.OWLOntology;
import org.semanticweb.owlapi.model.OWLOntologyManager;

import aterm.ATerm;
import aterm.ATermAppl;

import java.io.IOException;
import java.io.Writer;

/**
 * Author: Heng Jiang <br>
 * The University Of Bremen <br>
 * Date: 10-2007 <br><br>
 */
public class OWLATermRenderer extends AbstractOWLRenderer {

    public OWLATermRenderer(OWLOntologyManager owlOntologyManager) {
        super(owlOntologyManager);
    }

    public ATerm render(OWLOntology ontology) throws OWLException
    {
	//System.out.println("rere");
        OWLATermObjectRenderer ren = new OWLATermObjectRenderer(ontology, getOWLOntologyManager());
	//System.out.println("rere\n");
	ATerm aux = ren.term(ontology);
	System.out.println("Aux is: " + aux);
        return aux;

    }

    public void render(OWLOntology ontology, Writer writer) throws OWLRendererException {
        try {
            OWLATermObjectRenderer ren = new OWLATermObjectRenderer(ontology, writer, ontology.getOWLOntologyManager());
            writer.write(ren.term(ontology).toString());
            //ontology.accept(ren);
            writer.flush();
        }
        catch (IOException e) {
            throw new OWLRendererIOException(e);
        }catch(OWLException e){
        	e.printStackTrace();
        }
    }
}