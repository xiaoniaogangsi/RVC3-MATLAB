%ETS2 Elementary transform sequence in 2D
%
% This class and package allows experimentation with sequences of spatial
% transformations in 2D.
%
%          import ETS2.*
%          a1 = 1; a2 = 1;
%          E = Rz('q1') * Tx(a1) * Rz('q2') * Tx(a2)
%
% Operation methods::
%   fkine      forward kinematics
%   jacob0     geometric jacobian
%
% Information methods::
%   isjoint    test if transform is a joint
%   njoints    the number of joint variables
%   structure  a string listing the joint types
%
% Display methods::
%   display    display value as a string
%   plot       graphically display the sequence as a robot
%   teach      graphically display as robot and allow user control
%
% Conversion methods::
%   char       convert to string
%   string     convert to string with symbolic variables
%
% Operators::
%   *          compound two elementary transforms
%   +          compound two elementary transforms
%
% Notes::
% - The sequence is an array of objects of superclass ETS2, but with
%   distinct subclasses: Rz, Tx, Ty.
% - Use the command 'clear imports' after using ETS3.
%
%
% See also ETS3.

% Copyright 2022-2023 Peter Corke, Witold Jachimczyk, Remo Pillat

classdef ETS2
    properties
        what     % type of transform (string): Rx, Ry, etc
        param    % the constant numerical parameter (if not joint)
        qvar     % the integer joint index 1..N (if joint)
        qlim     % for prismatic joint, a 2 vector [min,max]
    end
    
    methods
        function obj = ETS2(what, x, varargin)
            %ETS2.ETS2  Create an ETS2 object
            %
            % E = ETS2(W, V) is a new ETS2 object that defines an elementary transform where
            % W is 'Rz', 'Tx' or 'Ty' and V is the paramter for the transform.  If V is a string
            % of the form 'qN' where N is an integer then the transform is considered
            % to be a joint.  Otherwise the transform is a constant.
            %
            % E = ETS2(E1) is a new ETS2 object that is a clone of the ETS2 object E1.
            %
            % See also ETS2.Rz, ETS2.Tx, ETS2.Ty.
            
            assert(nargin > 0, 'RTB:ETS2:ETS2:badarg', 'no arguments given');
            
            opt.qlim = [];
            opt = tb_optparse(opt, varargin);
            
            obj.qvar = NaN;
            obj.param = 0;
            
            if ~isempty(opt.qlim)
                assert(length(opt.qlim) == 2, 'ETS2: qlim must be a 2-vector');
            end
            obj.qlim = opt.qlim;
            
            if nargin > 1
                if isa(x, 'ETS2')
                    % clone it
                    obj.what = x.what;
                    obj.qvar = x.qvar;
                    obj.param = x.param;
                else
                    % create a new one
                    assert(ismember(what, {'Tx','Ty','R','Rz'}), 'ETS2: invalid transform type given');
                    if strcmp(what, 'R')
                        what = 'Rz';
                    end
                    if ischar(x)
                        obj.qvar = str2double(x(2:end));
                    else
                        obj.param = x;
                    end
                    obj.what = what;
                end
            end
        end
        
        function r = fkine(ets, q, varargin)
            %ETS2.fkine Forward kinematics
            %
            % ETS.fkine(Q, OPTIONS) is the forward kinematics, the pose of the end of the
            % sequence as an se2 object.  Q (1xN) is a vector of joint variables.
            %
            % ETS.fkine(Q, N, OPTIONS) as above but process only the first N elements
            % of the transform sequence.
            %
            % Options::
            %  'deg'     Angles are given in degrees.

            % Use numeric matrices to have full support for
            % symbolic computations
            r = eye(3);
            
            opt.deg = false;
            [opt,args] = tb_optparse(opt, varargin);
            
            if opt.deg
                opt.deg = pi/180;
            else
                opt.deg = 1;
            end
            
            n = length(ets);
            if ~isempty(args) && isreal(args{1})
                n = args{1};
            end
            assert(n>0 && n <= length(ets), 'RTB:ETS2:badarg', 'bad value of n given');
            
            for i=1:n
                e = ets(i);
                if e.isjoint
                    v = q(e.qvar);
                else
                    v = e.param;
                end
                switch e.what
                    case 'Tx'
                        r = r * tform2d(v,0,0);
                    case 'Ty'
                        r = r * tform2d(0,v,0);
                    case 'Rz'
                        r = r * tform2d(0,0,v*opt.deg);
                end
            end
            if isa(q, 'sym')
                r = simplify(r);  % simplify if it symbolic
            end
        end

        function tform = T(ets, qVal)

            tform = eye(3);

            if ets.isjoint
                v = qVal;
            else
                v = ets.param;
            end
            switch ets.what
                case 'Tx'
                    tform = tform * tform2d(v,0,0);
                case 'Ty'
                    tform = tform * tform2d(0,v,0);
                case 'Rz'
                    tform = tform * tform2d(0,0,v);
            end
            if nargin > 1 && isa(qVal, 'sym')
                tform = simplify(tform);  % simplify if it symbolic
            end
        end
        
        function b = isjoint(ets)
            %ETS2.isjoint  Test if transform is a joint
            %
            % E.isjoint is true if the transform element is a joint, that is, its
            % parameter is of the form 'qN'.
            b = ~isnan(ets.qvar);
        end
        
        function v = isprismatic(ets)
            %ETS2.isprismatic  Test if transform is prismatic joint
            %
            % E.isprismatic is true if the transform element is a joint, that is, its
            % parameter is of the form 'qN' and it controls a translation.
            v = isjoint(ets) && (ets.what(1) == 'T');
        end

        function v = isrevolute(ets)
            %ETS2.isrevolute  Test if transform is revolute joint
            %
            % E.isrevolute is true if the transform element is a joint, that is, its
            % parameter is of the form 'qN' and it controls a rotation.
            v = isjoint(ets) && (ets.what(1) == 'R');
        end
        
        function k = find(ets, j)
            %ETS2.find  Find joints in transform sequence
            %
            % E.find(J) is the index in the transform sequence ETS (1xN) corresponding
            % to the J'th joint.
            [~,k] = find([ets.qvar] == j);
        end
        
        function n = njoints(ets)
            %ETS2.njoints  Number of joints in transform sequence
            %
            % E.njoints is the number of joints in the transform sequence.
            %
            % See also ETS2.n.
            n = max([ets.qvar]);
        end
        
        function v = n(ets)
            %ETS2.n  Number of joints in transform sequence
            %
            % E.njoints is the number of joints in the transform sequence.
            %
            % Notes::
            % - Is a wrapper on njoints, for compatibility with SerialLink object.
            % See also ETS2.n.
            v = ets.njoints;
        end
        
        
        function s = string(ets)
            %ETS2.string  Convert to string with symbolic variables
            %
            % E.string is a string representation of the transform sequence where
            % non-joint parameters have symbolic names L1, L2, L3 etc.
            %
            % See also trchain.
            for i = 1:length(ets)
                e = ets(i);
                if e.isjoint
                    term = sprintf('%s(q%d)', e.what, e.qvar);
                else
                    term = sprintf('%s(L%d)', e.what, constant);
                    constant = constant + 1;
                end
                if i == 1
                    s = term;
                else
                    s = [s ' ' term]; %#ok<AGROW>
                end
            end
        end
        
        function out = mtimes(ets1, ets2)
            %ETS2.mtimes Compound transforms
            %
            % E1 * E2 is a sequence of two elementary transform.
            %
            % See also ETS2.plus.
            assert( isa(ets1,'ETS2') && isa(ets2,'ETS2'), 'ETS2: both operands must be of type ETS2, perhaps run ''clear import'', and start over');
            out = [ets1 ets2];
        end
        
        function out = plus(ets1, ets2)
            %ETS2.plus Compound transforms
            %
            % E1 + E2 is a sequence of two elementary transform.
            %
            % See also ETS2.mtimes.
            assert( isa(ets1,'ETS2') && isa(ets2,'ETS2'), 'ETS2: both operands must by of type ETS2, perhaps run ''clear import'', and start over');
            
            out = [ets1 ets2];
        end
        
        
        function s = structure(ets)
            %ETS2.structure  Show joint type structure
            %
            % E.structure is a character array comprising the letters 'R' or 'P' that
            % indicates the types of joints in the elementary transform sequence E.
            %
            % Notes::
            % - The string will be E.njoints long.
            %
            % See also SerialLink.config.
            s = '';
            for e = ets
                if e.qvar > 0
                    switch e.what
                        case {'Tx', 'Ty'}
                            s = [s 'P']; %#ok<AGROW>
                        case 'Rz'
                            s = [s 'R']; %#ok<AGROW>
                    end
                end
            end
        end
        
        function display(ets) %#ok<DISPLAY>
            %ETS2.display Display parameters
            %
            % E.display() displays the transform or transform sequence parameters in
            % compact single line format.
            %
            % Notes::
            % - This method is invoked implicitly at the command line when the result
            %   of an expression is an ETS2 object and the command has no trailing
            %   semicolon.
            %
            % See also ETS2.char.
            loose = strcmp( get(0, 'FormatSpacing'), 'loose'); %#ok<GETFSP>
            
            if loose
                disp(' ');
            end
            disp([inputname(1), ' = '])
            disp( char(ets) );
        end % display()
        
        function s = char(ets)
            %ETS2.char Convert to string
            %
            % E.char() is a string showing transform parameters in a compact format.  If E is a transform sequence (1xN) then
            % the string describes each element in sequence in a single line format.
            %
            % See also ETS2.display.
            s = '';
            
            function s = render(z)
                if isa(z, 'sym')
                    s = char(z);
                else
                    s = sprintf('%g', z);
                end
            end
            
            for e = ets
                if e.isjoint
                    s = [s sprintf('%s(q%d)', e.what, e.qvar) ]; %#ok<AGROW>
                else
                    s = [s sprintf('%s(%s)', e.what, render(e.param))]; %#ok<AGROW>
                    
                end
            end
        end
        
        function teach(robot, varargin)
            %ETS2.teach Graphical teach pendant
            %
            % Allow the user to "drive" a graphical robot using a graphical slider
            % panel.
            %
            % ETS.teach(OPTIONS) adds a slider panel to a current ETS plot. If no
            % graphical robot exists one is created in a new window.
            %
            % ETS.teach(Q, OPTIONS) as above but the robot joint angles are set to Q (1xN).
            %
            % Options::
            % '[no]deg'       Display angles in degrees (default true)
            %
            % GUI::
            % - The Quit (red X) button removes the teach panel from the robot plot.
            %
            % Notes::
            % - The currently displayed robots move as the sliders are adjusted.
            % - The slider limits are derived from the joint limit properties.  If not
            %   set then for
            %   - a revolute joint they are assumed to be [-pi, +pi]
            %   - a prismatic joint they are assumed unknown and an error occurs.
            % - The tool orientation is expressed using Yaw angle.
            %
            % See also ETS2.plot.
            
            %-------------------------------
            % parameters for teach panel
            bgcol = [135 206 250]/255;  %#ok<NASGU> % background color
            height = 0.06;  %#ok<NASGU> % height of slider rows
            %-------------------------------
            
            
            %---- handle options
            opt.deg = true;
            opt.orientation = {'eul', 'rpy', 'approach'};
            opt.d_2d = true;
            opt.callback = [];
            opt.vellipse = false;
            opt.fellipse = false;
            [opt,args] = tb_optparse(opt, varargin);

            if opt.vellipse
                opt.callback = @(r,q) vellipse(r,q);
            end

            if opt.fellipse
                opt.callback = @(r,q) fellipse(r,q);
            end
            
            if nargin == 1
                q = zeros(1,robot.n);
                % Set the default values for prismatic to the mean value 
                % of its largest and smallest allowed value.
                for i = 1:length(robot)
                    e = robot(i);
                    if isprismatic(e)
                        q(e.qvar) = mean(e.qlim);
                    end
                    % Check if there is an joint angle limit for the
                    % revolute joint, if so, and the range does not include
                    % zero, choose the mean value of its largest and
                    % smallest allowed value. Else, keep 0 as the default.
                    if isrevolute(e) && ~isempty(e.qlim)
                        if e.qlim(1) > 0 || e.qlim(2) < 0
                            q(e.qvar) = mean(e.qlim);
                        end
                    end
                end
            else
                q = varargin{1};
                % If the joint parameters are specified, check if the inputs
                % are legal.
                for i = 1:length(robot)
                    e = robot(i);
                    if isprismatic(e)
                        if q(e.qvar) < e.qlim(1) || q(e.qvar) > e.qlim(2)
                            error("Prismatic Joint Parameter Out of Range!")
                        end
                        if q(e.qvar) == 0
                            error("Prismatic Joint Parameter Should Not Be Zero!")
                            % Set q(e.qvar) to zero will cause 'Matrix'
                            % property value to be invalid in the scaling
                            % step of ETS2/animate.
                        elseif q(e.qvar) < 0
                            error("Prismatic Joint Parameter Should Not Be Negative!")
                        end
                    end
                    if isrevolute(e)
                        if ~isempty(e.qlim)
                            if q(e.qvar) < e.qlim(1) || q(e.qvar) > e.qlim(2)
                                error("Prismatic Joint Parameter Out of Range!")
                            end
                        else    % If qlim not set, use [-pi, +pi]
                            if q(e.qvar) < -pi || q(e.qvar) > pi
                                error("Revolute Joint Parameter Out of Range!")
                            end
                        end
                    end
                end
            end

            % Save a copy for the initial q, used for scaling
            q_initial = q(:,:);
            robot.plot(q, q_initial, args{2:end});
            
            RTBPlot.install_teach_panel('ETS2', robot, q, q_initial, opt);
        end
        
        
        function plot(ets, qq, q_initial, varargin)
            %ETS2.plot Graphical display and animation
            %
            % ETS.plot(Q, options) displays a graphical animation of a robot based on
            % the transform sequence.  Constant translations are represented as pipe segments, rotational joints as cylinder, and
            % prismatic joints as boxes. The robot is displayed at the joint angle Q (1xN), or
            % if a matrix (MxN) it is animated as the robot moves along the M-point trajectory.
            %
            % Options::
            % 'workspace', W    Size of robot 3D workspace, W = [xmn, xmx ymn ymx zmn zmx]
            % 'floorlevel',L    Z-coordinate of floor (default -1)
            %-
            % 'delay',D         Delay betwen frames for animation (s)
            % 'fps',fps         Number of frames per second for display, inverse of 'delay' option
            % '[no]loop'        Loop over the trajectory forever
            % '[no]raise'       Autoraise the figure
            % 'movie',M         Save an animation to the movie M
            % 'trail',L         Draw a line recording the tip path, with line style L
            %-
            % 'scale',S         Annotation scale factor
            % 'zoom',Z          Reduce size of auto-computed workspace by Z, makes
            %                   robot look bigger
            % 'ortho'           Orthographic view
            % 'perspective'     Perspective view (default)
            % 'view',V          Specify view V='x', 'y', 'top' or [az el] for side elevations,
            %                   plan view, or general view by azimuth and elevation
            %                   angle.
            % 'top'             View from the top.
            %-
            % '[no]shading'     Enable Gouraud shading (default true)
            % 'lightpos',L      Position of the light source (default [0 0 20])
            % '[no]name'        Display the robot's name
            %-
            % '[no]wrist'       Enable display of wrist coordinate frame
            % 'xyz'             Wrist axis label is XYZ
            % 'noa'             Wrist axis label is NOA
            % '[no]arrow'       Display wrist frame with 3D arrows
            %-
            % '[no]tiles'       Enable tiled floor (default true)
            % 'tilesize',S      Side length of square tiles on the floor (default 0.2)
            % 'tile1color',C   Color of even tiles [r g b] (default [0.5 1 0.5]  light green)
            % 'tile2color',C   Color of odd tiles [r g b] (default [1 1 1] white)
            %-
            % '[no]shadow'      Enable display of shadow (default true)
            % 'shadowcolor',C   Colorspec of shadow, [r g b]
            % 'shadowwidth',W   Width of shadow line (default 6)
            %-
            % '[no]jaxes'       Enable display of joint axes (default false)
            % '[no]jvec'        Enable display of joint axis vectors (default false)
            % '[no]joints'      Enable display of joints
            % 'jointcolor',C    Colorspec for joint cylinders (default [0.7 0 0])
            % 'jointcolor',C    Colorspec for joint cylinders (default [0.7 0 0])
            % 'jointdiam',D     Diameter of joint cylinder in scale units (default 5)
            %-
            % 'linkcolor',C     Colorspec of links (default 'b')
            %-
            % '[no]base'        Enable display of base 'pedestal'
            % 'basecolor',C     Color of base (default 'k')
            % 'basewidth',W     Width of base (default 3)
            %
            % The options come from 3 sources and are processed in order:
            % - Cell array of options returned by the function PLOTBOTOPT (if it exists)
            % - Cell array of options given by the 'plotopt' option when creating the
            %   SerialLink object.
            % - List of arguments in the command line.
            %
            % Many boolean options can be enabled or disabled with the 'no' prefix.  The
            % various option sources can toggle an option, the last value encountered is used.
            %
            % Graphical annotations and options::
            %
            % The robot is displayed as a basic stick figure robot with annotations
            % such as:
            % - shadow on the floor
            % - XYZ wrist axes and labels
            % - joint cylinders and axes
            % which are controlled by options.
            %
            % The size of the annotations is determined using a simple heuristic from
            % the workspace dimensions.  This dimension can be changed by setting the
            % multiplicative scale factor using the 'mag' option.
            %
            % Figure behaviour::
            %
            % - If no figure exists one will be created and the robot drawn in it.
            % - If no robot of this name is currently displayed then a robot will
            %   be drawn in the current figure.  If hold is enabled (hold on) then the
            %   robot will be added to the current figure.
            % - If the robot already exists then that graphical model will be found
            %   and moved.
            %
            %
            % Notes::
            % - The options are processed when the figure is first drawn, to make different options come
            %   into effect it is neccessary to clear the figure.
            % - Delay betwen frames can be eliminated by setting option 'delay', 0 or
            %   'fps', Inf.
            % - The size of the plot volume is determined by a heuristic for an all-revolute
            %   robot.  If a prismatic joint is present the 'workspace' option is
            %   required.  The 'zoom' option can reduce the size of this workspace.
            %
            % See also ETS2.teach, SerialLink.plot3d.
            
            % heuristic to figure robot size
            reach = 0;
            for e=ets
                switch e.what
                    case {'Tx', 'Ty', 'Tz'}
                        if isjoint(e)
                            reach = reach + e.qlim(2);
                        else
                            reach = reach + e.param;
                        end
                end
            end
            
            opt = RTBPlot.plot_options([], [varargin 'reach', 3, 'top']);
            draw_ets(ets, qq, opt);
            
            set(gca, 'Tag', 'RTB.plot');
            set(gcf, 'Units', 'Normalized');
            
            if opt.raise
                % note this is a very time consuming operation
                figure(gcf);
            end
            
            if strcmp(opt.projection, 'perspective')
                set(gca, 'Projection', 'perspective');
            end
            
            if ischar(opt.view)
                switch opt.view
                    case 'top'
                        view(0, 90);
                    case 'x'
                        view(0, 0);
                    case 'y'
                        view(90, 0)
                    otherwise
                        error('rtb:plot:badarg', 'view must be: x, y, top')
                end
            elseif isnumeric(opt.view) && length(opt.view) == 2
                view(opt.view)
            end
            
            % enable mouse-based 3D rotation
            rotate3d on
            
            ets.animate(qq, q_initial);
        end
        
        function animate(~, qq, q_initial)
            handles = findobj('Tag', 'ETS2');
            h = handles.UserData;
            opt = h.opt;
            
            ets = h.ets;
            for q = qq'
                for i=1:length(ets)
                    
                    % create the transform for displaying this element (joint cylinder + link)
                    e = ets(i);
                    if i == 1
                        T = se2;
                    else
                        T = se2(ets.fkine(q, i-1, 'setopt', opt));
                    end
                    
                    % update the pose of the corresponding graphical element (joint cylinder + link)
                    set(h.element(i), 'Matrix', se2To3(T).tform);
                    
                    if isprismatic(e)
                        % for prismatic joints, scale the box
                        original = q_initial(e.qvar);
                        switch e.what
                            case 'Tx'
                                set(h.pjoint(e.qvar), 'Matrix', diag([q(e.qvar)/original 1 1 1]));
                            case 'Ty'
                                set(h.pjoint(e.qvar), 'Matrix', diag([1 q(e.qvar)/original 1 1]));
                        end
                    end
                end
                
                % update the wrist frame
                T = se2(ets.fkine(q, 'setopt', opt));
                if ~isempty(h.wrist)
                    plottform2d(T.tform, 'handle', h.wrist);
                end
                
                % render and pause
                if opt.delay > 0
                    pause(opt.delay);
                    drawnow
                end
            end
        end
        
        function J = jacob0(ets, q, ee)
            %jacob0 Compute the geometric Jacobian for the ETS
            %   JAC = jacob0(ETS, Q) computes
            %   the geometric Jacobian for the last link in ETS
            %   under the configuration Q. The Jacobian matrix JAC is of size
            %   3xN, where N is the number of degrees of freedom. The
            %   Jacobian maps joint-space velocity to the Cartesian space
            %   end-effector velocity relative to the base coordinate frame.
            %   The first row has the rotational dof, the last 2 rows have
            %   the translational dof.
            %
            %   JAC = jacob0(ETS, Q, ENDEFFECTORNAME) computes
            %   the geometric Jacobian for the body ENDEFFECTORNAME

            rbt = ets2rbt(ets);

            if nargin < 3
                % If no end effector is provided, use the last link in the
                % RBT.
                ee =  rbt.Bodies{end}.Name;
            end

            % Calculate 3D Jacobian
            J3d = rbt.geometricJacobian(q, ee);

            % Extract theta rate (rot around z), and x y (translation) for
            % 2D version of Jacobian.
            J = J3d(3:5,:); 
        end        
    end
    
    methods (Access=private)
        
        function h_ = draw_ets(ets, q, opt)
            
            clf            
            
            axis(opt.workspace);
            
            s = opt.scale;
            % create an axis
            ish = ishold();
            if ~ishold
                % if hold is off, set the axis dimensions
                axis(opt.workspace);
                hold on
            end
            
            group = hggroup('Tag', 'ETS2');
            h.group = group;
            
            % create the graphical joint and link elements
            for i=1:length(ets)
                e = ets(i);
                
                if opt.debug
                    fprintf('create graphics for %s\n', e.char );
                end
                
                % create a graphical depiction of the transform element
                % This is drawn to resemble orthogonal plumbing.
                
                if i == 1
                    T = se2;
                else
                    T = se2(ets.fkine(q, i-1, 'setopt', opt));
                end
                
                % create the transform for displaying this element (joint cylinder + link)
                Tdisp = se2To3(T);
                h.element(i) = hgtransform('Tag', sprintf('element%d', i), 'Matrix', Tdisp.tform, 'Parent', h.group);
                
                if isjoint(e)
                    % it's a joint element: revolute or prismatic
                    switch e.what
                        case 'Tx'
                            h.pjoint(e.qvar) = hgtransform('Tag', 'prismatic', 'Parent', h.element(i), 'Matrix', [1 0 0 q(e.qvar); 0 1 0 0; 0 0 1 0; 0 0 0 1]);
                            RTBPlot.box('x', opt.jointdiam*s, [0 q(e.qvar)], opt.pjointcolor, [], 'Parent', h.pjoint(e.qvar));
                        case 'Ty'
                            h.pjoint(e.qvar) = hgtransform('Tag', 'prismatic', 'Parent', h.element(i), 'Matrix', [1 0 0 0; 0 1 0 q(e.qvar); 0 0 1 0; 0 0 0 1]);
                            RTBPlot.box('y', opt.jointdiam*s, [0 q(e.qvar)], opt.pjointcolor, [], 'Parent', h.pjoint(e.qvar));
                        case 'Rz'
                            RTBPlot.cyl('z', opt.jointdiam*s, opt.jointlen*s*[-1 1], opt.jointcolor, [], 'Parent', h.element(i));
                    end
                else
                    % it's a constant transform
                    switch e.what
                        case 'Tx'
                            RTBPlot.cyl('x', s, [0 e.param], opt.linkcolor, [], 'Parent', h.element(i));
                        case 'Ty'
                            RTBPlot.cyl('y', s, [0 e.param], opt.linkcolor, [], 'Parent', h.element(i));
                        case 'Rz'
                            RTBPlot.cyl('z', opt.jointdiam*s, opt.jointlen*s*[-1 1], opt.linkcolor, [], 'Parent', h.element(i));
                    end
                end
                
                assert( ~(opt.jaxes && opt.jvec), 'RTB:ETS2:plot:badopt', 'Can''t specify ''jaxes'' and ''jvec''')
                
                % create the joint axis line
                if opt.jaxes
                    if e.isjoint
                        line('XData', [0 0], ...
                            'YData', [0 0], ...
                            'ZData', 14*s*[-1 1], ...
                            'LineStyle', ':', 'Parent', h.element(i));
                        
                        % create the joint axis label
                        text(0, 0, 14*s, sprintf('q%d', e.qvar), 'Parent', h.element(i))
                    end
                end
                
                % create the joint axis vector
                if opt.jvec
                    if e.isjoint
                        daspect([1 1 1]);
                        %ha = arrow3([0 0 -12*s], [0 0 15*s], 'c');
                        ha = quiver3([0 0 -12*s], 0, 0, 27*s, 'c');
                        set(ha, 'Parent', h.element(i));
                        
                        % create the joint axis label
                        text(0, 0, 20*s, sprintf('q%d', e.qvar), 'Parent', h.element(i))
                    end
                end
                
            end
            
            % display the wrist coordinate frame
            if opt.wrist
                if opt.arrow
                    % compute arrow3 scale factor...
                    d = axis(gca);
                    if length(d) == 4
                        d = norm( d(3:4)-d(1:2) ) / 72;
                    else
                        d = norm( d(4:6)-d(1:3) ) / 72;
                    end
                    extra = {'arrow', 'LineWidth', 1.5*s/d};
                else
                    extra = {};
                end
%                 h.wrist = trplot2(eye(3,3), 'labels', upper(opt.wristlabel), ...
%                     'color', 'k', 'length', opt.wristlen*s, extra{:});
%                 h.wrist = plottform2d(eye(3,3), labels=upper(opt.wristlabel), ...
%                     color="k", length=opt.wristlen*s), extra{:});
                    h.wrist = plottform2d(eye(3,3), color="k", length=opt.wristlen*s);
            else
                h.wrist = [];
            end
            
            xlabel('X')
            ylabel('Y')
            zlabel('Z')
            grid on
            
            % restore hold setting
            if ~ish
                hold off
            end
            
            h.opt = opt;
            h.ets = ets;
            
            if nargout > 0
                h_ = h;
            end
            
            % attach the handle structure to the top graphical element
            
            h.q = q;
            
            set(group, 'UserData', h);
        end

    end
    
    methods (Static)
        function obj = Rz(varargin)
            %Rz Construct ETS2 object for rotation around z axis
            [varargin{:}] = convertStringsToChars(varargin{:});
            obj = ETS2('Rz', varargin{:});
        end
        
        function obj = Tx(varargin)
            %Tx Construct ETS2 object for translation along x axis
            [varargin{:}] = convertStringsToChars(varargin{:});
            obj = ETS2('Tx', varargin{:});
        end
        
        function obj = Ty(varargin)
            %Ty Construct ETS2 object for translation along y axis
            [varargin{:}] = convertStringsToChars(varargin{:});
            obj = ETS2('Ty', varargin{:});
        end
    end    
end