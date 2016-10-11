;;; shader-program.lisp
;;;; Please see the licence.txt for the CLinch

(in-package #:clinch)

(defclass shader-program ()
  ((name
    :reader name
    :initform nil)
   (program
    :reader program
    :initform nil)
   (attributes
    :reader shader-program-attributes
    :initform nil)
   (uniforms
    :reader shader-program-uniforms
    :initform nil)
   (key :initform (gensym "shader-program")
	:reader key))
  
  (:documentation "Creates and keeps track of the shader-program objects. Requires an UNLOAD call when you are done. Bind Buffer functions are in Buffer.l"))

(defmethod initialize-instance :after ((this shader-program) &key
							       vertex-shader
							       fragment-shader
							       geometry-shader
							       name
							       attributes
							       uniforms
							       defines
							       undefs
							       delete-shaders)
  "Create the shader program. Currently there is no way to change the shader. You must make a new one."

  (build-shader-program this
			:vertex-shader vertex-shader
			:fragment-shader fragment-shader
			:geometry-shader geometry-shader
			:attributes attributes
			:uniforms uniforms
			:defines defines
			:undefs undefs
			:delete-shaders delete-shaders)

  (add-uncollected this))



(defmethod attach-shader ((program shader-program) (shader shader))
  
  (when (id shader)    
    (gl:attach-shader (program program) (id shader))))

(defmethod detach-shader ((program shader-program) (shader shader))

  (when (and (program program) (id shader))
    (gl:detach-shader (program program) (id shader))))

(defmethod build-shader-program ((this null) &key 
					       vertex-shader
					       fragment-shader
					       geometry-shader
					       attributes
					       uniforms
					       defines
					       undefs
					       delete-shaders)
  (make-instance 'shader-program 
		 :vertex-shader vertex-shader
		 :fragment-shader fragment-shader
		 :geometry-shader geometry-shader
		 :attributes attributes
		 :uniforms uniforms
		 :defines defines
		 :undefs undefs
		 :delete-shaders delete-shaders))


(defmethod build-shader-program ((this shader-program) &key
							 vertex-shader
							 fragment-shader
							 geometry-shader
							 attributes
							 uniforms
							 defines
							 undefs
							 delete-shaders)
  (!
   (unload-all-dependants (key this))
   
   (with-slots ((program program)) this
     (let ((vs vertex-shader)
	   (fs fragment-shader)
	   (geo geometry-shader))

       (typecase vs
	 (string
	  (add-dependent this
			 (setf vs (make-instance 'vertex-shader :code vs :defs defines :undefs undefs))))
	 (shader t)
	 (t (if vs
		(error "Vertex shader is type ~A, which is not a string or a vertex shader." (type-of vs))
		(error "No vertex shader given."))))

       (typecase fs
	 (string
	  (add-dependent this
			 (setf fs (make-instance 'fragment-shader :code fs :defs defines :undefs undefs))))
	 (shader t)
	 (t (if fs
		(error "Fragment shader is type ~A, which is not a string or a vertex shader." (type-of fs))
		(error "No fragment shader given!"))))

       (typecase geo
	 (string
	  (add-dependent this
			 (setf geo (make-instance 'vertex-shader :code geo :defs defines :undefs undefs))))
	 (shader t)
	 (null t)
	 (t (error "Geometry shader is type ~A, which is not a string or a vertex shader." (type-of geo))))

       (unless program (setf program (gl:create-program)))

       ;; You can attach the same shader to multiple different programs.
       (attach-shader this vs)
       (attach-shader this fs)
       (when geo
	 (attach-shader program geo))


       ;; Don't forget to link the program after attaching the
       ;; shaders. This step actually puts the attached shader together
       ;; to form the program.
       (gl:link-program program)

       (when delete-shaders 

	 (format t "DELETEING SHADERS!!!!~%")

	 (detach-shader this vs)
	 (detach-shader this fs)
	 (when geo
	   (detach-shader this geo)))

       (setf (slot-value this 'uniforms) (make-hash-table :test 'equal))
       (setf (slot-value this 'attributes) (make-hash-table :test 'equal))

       (trivial-garbage:cancel-finalization this)
       (add-uncollected this)
       (trivial-garbage:finalize this
				 (let ((program-val program)
				       (key (key this)))
				   
				   (lambda ()
				     (remhash key *uncollected*)
				     (!!
				      (unload-all-dependants key)
				      (gl:delete-program program-val)))))

       (when attributes
	 (loop for (name type) in attributes
	    for location = (gl:get-attrib-location program name)
	    if (>= location 0)
	    do (setf (gethash name (slot-value this 'attributes))
		     (cons type location))
	    else do (format t "could not find attribute ~A!~%" name)))
       

       (when uniforms
	 (loop for (name type) in uniforms
	    for location = (gl:Get-Uniform-Location program name)
	    if (>= location 0)
	    do (setf (gethash name (slot-value this 'uniforms))
		     (cons type location))
	    else do (format t "could not find uniform ~A!~%" name)))))))

(defmethod pullg ((this shader-program) &key)
  "Returns shader-program's available information such as shader source, uniforms and attributes."
  (!
   (append
    (loop for i in (gl:get-attached-shaders (program this))
       collect (list (cffi:foreign-enum-keyword '%gl::enum 
						(gl:get-shader i :shader-type))
		     (gl:get-shader-source i)))
    (list (list :uniforms (list-shader-uniforms this))
	  (list :attributes (list-shader-attributes this))))))

(defmethod use-shader-program ((this shader-program) &key)
  "Start using the shader-program."
  (gl:use-program (program this)))

(defmethod list-shader-uniforms ((this shader-program))
  "List the shader-program's uniform arguments."
  (! (loop for i from 0 below (gl:get-program (program this) :active-uniforms) 
	collect (cons i (multiple-value-list (gl:get-active-uniform (program this) i))))))

(defmethod list-shader-attributes ((this shader-program))
  "List the shader-program's attribute arguments."
  (! (loop for i from 0 below (gl:get-program (program this) :active-attributes) 
	collect (cons i (multiple-value-list (gl:get-active-attrib (program this) i))))))

;;doesn't work yet...
;; (defmethod list-shader-uniform-blocks ((this shader-program))
;;   (! (loop for i from 0 below (gl:get-program (program this) :active-uniform-blocks) 
;; 	collect (cons i (multiple-value-list (gl:get-active-uniform-block-name (program this) i))))))

(defmethod get-uniform-id ((this shader-program) (id integer))
  "Shaders pass information by using named values called Uniforms and Attributes. If we are using the raw id, this returns it."
  (when (and id (>= id 0)) id))

(defmethod get-uniform-id ((this shader-program) (uniform string))
  "Shaders pass information by using named values called Uniforms and Attributes. This gets the gl id of a uniform name."
  (let ((id (gethash uniform
		     (slot-value this 'uniforms))))
    (when (and id (>= (cdr id) 0)) id)))

(defmethod get-attribute-id ((this shader-program) (id integer))
  "Shaders pass information by using named values called Uniforms and Attributes. If we are using the raw id, this returns it."
  (when (and id
	     (>= id 0))
    id))

(defmethod get-attribute-id ((this shader-program) (attribute string))
  "Shaders pass information by using named values called Uniforms and Attributes. This gets the gl id of a attribute name."
  (let ((id (gethash attribute
		     (slot-value this 'attributes))))
    (when (and id
	       (>= (cdr id) 0))
      id)))


(defmethod attach-uniform ((this shader-program) (uniform string) value)
  "Shaders pass information by using named values called Uniforms and Attributes. This sets a uniform to value."
  (let ((ret (get-uniform-id this uniform)))

    (when ret
      ;;(unless (eq (gethash ret *current-shader-uniforms*) value)
      (setf (gethash ret *current-shader-uniforms*) value)
      
      (destructuring-bind (type . id) ret
	
	(let ((f (case type
		   (:float #'gl:uniformf)
		   (:int #'gl:uniformi)
		   (:matrix (lambda (id value)
			      (gl:uniform-matrix id 2 (cond
							((arrayp value) value)
							((typep value 'node) (transform
									      value))
							(t (error "Unknown Type in attach-uniform!")))))))))
	  
	  (if (listp value)
	      (apply f id value)
	      (apply f id (list value))))))))

(defmethod attach-uniform ((this shader-program) (uniform string) (matrix array))
  "Shaders pass information by using named values called Uniforms and Attributes. This sets a uniform to a matrix value."

  (let ((ret (get-uniform-id this uniform)))
    (when ret 
      ;;(unless (eq (gethash ret *current-shader-uniforms*) ret)
      (setf (gethash ret *current-shader-uniforms*) ret)
      (destructuring-bind (type . id) ret

	(cffi:with-pointer-to-vector-data (foreign-matrix matrix)
	  (case (floor (sqrt (length matrix)))
	    (4 (%gl:uniform-matrix-4fv id 1 nil foreign-matrix))
	    (3 (%gl:uniform-matrix-3fv id 1 nil foreign-matrix))
	    (2 (%gl:uniform-matrix-2fv id 1 nil foreign-matrix))))))))



(defmethod attach-uniform ((this shader-program) (uniform string) (matrix node))
  "Shaders pass information by using named values called Uniforms and Attributes. This sets a uniform to the matrix of a node."

  (let ((ret (get-uniform-id this uniform)))
    (when ret 
      ;;(unless (eq (gethash ret *current-shader-uniforms*) matrix)
      (setf (gethash ret *current-shader-uniforms*) matrix)
      
      (let ((ret (get-uniform-id this uniform)))
	(when ret 
	  (destructuring-bind (type . id) ret
	    
	    (gl::with-foreign-matrix (foreign-matrix (transform matrix))
	      (%gl:uniform-matrix-4fv id 1 nil foreign-matrix))))))))

(defmethod bind-static-values-to-attribute ((this shader-program) name vals)
  "It is possible to bind static information to an attribute. That's what this does."
  (let ((id (cdr (get-attribute-id this name))))
    (when id 
      (gl:disable-vertex-attrib-array id)
      (apply #'gl:vertex-attrib id vals))))


(defmethod unload ((this shader-program) &key)
  "Unloads and releases all shader-program resources."

  (with-slots ((program program)) this
    
    (trivial-garbage:cancel-finalization this)
    (remove-uncollected this)

    (unload-all-dependants (key this))

    (when program

      (gl:delete-program program)
      (setf program nil))
    
    (setf (slot-value this 'uniforms) nil
	  (slot-value this 'attributes) nil
	  (slot-value this 'name) nil)))


(defmethod shader-program-attribute ((this shader-program) key)
  "Gets a shader-program attribute"
  (gethash key (slot-value this 'shader-program-program-attribute)))

(defmethod (setf shader-program-attribute) (value (this shader-program) key)
  "Sets a shader-program attribute."
  (setf (gethash key (slot-value this 'shader-program-attribute)) value))

(defmethod remove-shader-program-attribute ((this shader-program) key)
  "Removes a shader-program attribute"
  (remhash key (slot-value this 'shader-program-attribute)))

(defmethod shader-program-uniform ((this shader-program) key)
  "Gets a shader-program uniform"
  (gethash key (slot-value this 'shader-program-uniform)))

(defmethod (setf shader-program-uniform) (value (this shader-program) key)
  "Sets a shader-program uniform."
  (setf (gethash key (slot-value this 'shader-program-uniform)) value))

(defmethod remove-shader-program-uniform ((this shader-program) key)
  "Removes a shader-program uniform"
  (remhash key (slot-value this 'shader-program-uniform)))

(defparameter *generic-single-texture-shader* nil)
(defun get-generic-single-texture-shader ()
  "Creates/returns a shader-program which blits a texture to an entity.
   Uniforms:
    P: projection matrix
    M: model-view matrix
    t1: texture
   Attributes:
    v: Vertexes
    tc1: texture coordinates"
    
  (if (and *generic-single-texture-shader* (program *generic-single-texture-shader*))
      *generic-single-texture-shader*
      (setf *generic-single-texture-shader*
	    (make-instance 'clinch:shader-program
			   :name "generic-single-texture-shader"
			   :vertex-shader (alexandria:read-file-into-string
					   (concatenate 'string 
							(directory-namestring
							 (asdf:system-relative-pathname :clinch "clinch.asd"))
							"shaders/generic-single-texture-shader.vert"))
			   :fragment-shader (alexandria:read-file-into-string
					     (concatenate 'string 
							  (directory-namestring
							   (asdf:system-relative-pathname :clinch "clinch.asd"))
							  "shaders/generic-single-texture-shader.frag"))
			   :uniforms '(("P" :matrix)
				       ("M" :matrix)
				       ("t1" :int))
			   :attributes '(("tc1" :float)
					 ("v" :float))))))

(defparameter *generic-solid-phong-shader* nil)
(defun get-generic-solid-phong-shader ()
  "Creates/returns a shader-program which uses simple phong shading with a single color.
   Uniforms:
    P: projection matrix
    M: model-view matrix
    ambientLight: Ambient Light Color
    lightDirection: Direction of light
    lightIntensity: Color of light
    color: color of object
   Attributes:
    v: Vertexes"
    
  (if (and *generic-solid-phong-shader* (program *generic-solid-phong-shader*))
      *generic-solid-phong-shader*
      (setf *generic-solid-phong-shader*
	    (make-instance 'clinch:shader-program
			   :name "generic-solid-phong-shader"
			   :vertex-shader (alexandria:read-file-into-string
					   (concatenate 'string 
							(directory-namestring
							 (asdf:system-relative-pathname :clinch "clinch.asd"))
							"shaders/generic-solid-phong-shader.vert"))
			   :fragment-shader (alexandria:read-file-into-string
					     (concatenate 'string 
							  (directory-namestring
							   (asdf:system-relative-pathname :clinch "clinch.asd"))
							  "shaders/generic-solid-phong-shader.frag"))
			   :uniforms '(("P" :matrix)
				       ("M" :matrix)
				       ("ambientLight" :float)
				       ("lightDirection" :float)
				       ("lightIntensity" :float)
				       ("color" :float))
			   :attributes '(("v" :float))))))

(defparameter *generic-single-diffuse-light-shader* nil)
(defun get-generic-single-diffuse-light-shader ()
  (if (and *generic-single-diffuse-light-shader* (program *generic-single-diffuse-light-shader*))
      *generic-single-diffuse-light-shader*
      (setf *generic-single-diffuse-light-shader*
	    (make-instance 'clinch:shader-program
			   :name "generic-single-diffuse-light-shader"
			   :vertex-shader (alexandria:read-file-into-string
					   (concatenate 'string 
							(directory-namestring
							 (asdf:system-relative-pathname :clinch "clinch.asd"))
							"clinch-classimp/generic-single-diffuse-light-shader.vert"))
			   :fragment-shader (alexandria:read-file-into-string
					   (concatenate 'string 
							(directory-namestring
							 (asdf:system-relative-pathname :clinch "clinch.asd"))
							"clinch-classimp/generic-single-diffuse-light-shader.frag"))
			   
			   :uniforms '(("M" :matrix)
				       ("N" :matrix)
				       ("P" :matrix)
				       ("t1" :int)
				       ("ambientLight" :float)
				       ("lightDirection" :float)
				       ("lightIntensity" :float))
				       
			   :attributes '(("v" :float)
					 ("n" :float)
					 ("c" :float)
					 ("tc1" :float))))))


(defparameter *test-shader* nil)
(defun get-test-shader ()

  "none of this matters!
  Creates/returns a shader-program which uses simple phong shading with a single color.
   Uniforms:
    P: projection matrix
    M: model-view matrix
    ambientLight: Ambient Light Color
    lightDirection: Direction of light
    lightIntensity: Color of light
    color: color of object
   Attributes:
    v: Vertexes"
    
  (if (and *test-shader* (program *test-shader*))
      *test-shader*
      (setf *test-shader*
	    (make-instance 'clinch:shader-program
			   :name "test-shader"
			   :vertex-shader (alexandria:read-file-into-string
					   (concatenate 'string 
							(directory-namestring
							 (asdf:system-relative-pathname :clinch "clinch.asd"))
							"shaders/test-shader.vert"))
			   :fragment-shader (alexandria:read-file-into-string
					     (concatenate 'string 
							  (directory-namestring
							   (asdf:system-relative-pathname :clinch "clinch.asd"))
							  "shaders/test-shader.frag"))
			   :uniforms '(("P" :matrix)
				       ("M" :matrix)
				       ("ambientLight" :float)
				       ("lightDirection" :float)
				       ("lightIntensity" :float)
				       ("color" :float))
			   :attributes '(("v" :float))))))



